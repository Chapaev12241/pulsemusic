import SwiftUI
import AVFoundation
import Combine
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct PulsePreviewClip: Equatable {
    let start: Double
    let end: Double
    static func interval(duration: Double) -> PulsePreviewClip? {
        guard duration.isFinite, duration > 1.5 else { return nil }
        let start = duration >= 30 ? min(max(8, duration * 0.4), duration - 15) : duration * 0.35
        let end = min(duration - 0.1, start + 15)
        guard start >= 0.5, end > start else { return nil }
        return PulsePreviewClip(start: start, end: end)
    }
}

// Auditioning a picker row has no history or system Now Playing side effects.
@MainActor
final class PulseTrackPreview: ObservableObject {
    @Published private(set) var trackID: String?
    @Published private(set) var loading = false
    @Published private(set) var playing = false
    @Published private(set) var error: String?
    private weak var store: PulseStore?
    private var player: AVPlayer?
    private var asset: AVURLAsset?
    private var load: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var finish: Task<Void, Never>?
    private var boundary: Any?
    private var status: NSKeyValueObservation?
    private var itemStatus: NSKeyValueObservation?
    private var volume: AnyCancellable?
    private var notifications: [NSObjectProtocol] = []
    private var session: UUID?
    private var request = UUID()

    init(store: PulseStore) {
        self.store = store
        volume = store.$volume.sink { [weak self] value in self?.player?.volume = Float(value) }
        #if os(iOS)
        observe(UIApplication.willResignActiveNotification)
        observe(AVAudioSession.interruptionNotification)
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { @MainActor in self?.stop(resume: false) } }
        })
        #else
        observe(NSApplication.willResignActiveNotification)
        #endif
    }
    private func observe(_ name: Notification.Name) {
        notifications.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.stop(resume: false) } })
    }
    deinit {
        load?.cancel(); deadline?.cancel(); finish?.cancel()
        for observer in notifications { NotificationCenter.default.removeObserver(observer) }
    }
    func toggle(_ track: PulseTrack) {
        if trackID == track.id { stop(); return }
        guard let store, let remote = URL(string: track.audio), remote.scheme == "https", remote.host == PulseAPI.base.host else { return }
        clearPlayer()
        error = nil
        if session == nil { session = store.beginTrackPreview { [weak self] in self?.stop(resume: false) } }
        let stamp = UUID(); request = stamp; trackID = track.id; loading = true
        let url = PulseDownloads.localURL(track.id) ?? remote
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        self.asset = asset
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            guard let self, self.request == stamp else { return }
            self.fail("Отрывок не загрузился. Попробуй ещё раз.")
        }
        load = Task { [weak self] in
            do {
                let length = try await asset.load(.duration)
                try Task.checkCancellation()
                guard let self, self.request == stamp else { return }
                guard let clip = PulsePreviewClip.interval(duration: length.seconds) else { throw URLError(.cannotDecodeContentData) }
                #if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
                try AVAudioSession.sharedInstance().setActive(true)
                #endif
                let item = AVPlayerItem(asset: asset)
                item.forwardPlaybackEndTime = CMTime(seconds: clip.end, preferredTimescale: 600)
                item.preferredForwardBufferDuration = 6
                let candidate = AVPlayer(playerItem: item)
                candidate.volume = 0
                candidate.automaticallyWaitsToMinimizeStalling = true
                self.player = candidate
                self.itemStatus = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    if item.status == .failed { Task { @MainActor in if self?.request == stamp { self?.fail("Не удалось прослушать этот трек.") } } }
                }
                // A new AVPlayer stays paused and muted until the middle seek completes.
                let seeked = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    candidate.seek(to: CMTime(seconds: clip.start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { continuation.resume(returning: $0) }
                }
                try Task.checkCancellation()
                guard self.request == stamp, self.player === candidate else { return }
                let position = candidate.currentTime().seconds
                guard seeked, position.isFinite, position >= max(0.25, clip.start - 0.5), position < clip.end else {
                    self.fail("Не удалось перейти к отрывку. Попробуй другой трек."); return
                }
                self.status = candidate.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
                    Task { @MainActor in
                        guard let self, self.request == stamp, self.player === player else { return }
                        self.loading = player.timeControlStatus != .playing
                        if player.timeControlStatus == .playing { self.deadline?.cancel(); self.deadline = nil }
                    }
                }
                self.boundary = candidate.addBoundaryTimeObserver(forTimes: [NSValue(time: CMTime(seconds: clip.end - 0.05, preferredTimescale: 600))], queue: .main) { [weak self] in
                    Task { @MainActor in if self?.request == stamp { self?.stop() } }
                }
                candidate.volume = Float(store.volume)
                self.playing = true
                candidate.play()
                self.finish = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64((clip.end - clip.start + 3) * 1_000_000_000)) } catch { return }
                    guard let self, self.request == stamp else { return }; self.stop()
                }
            } catch is CancellationError { }
            catch { if let self, self.request == stamp { self.fail("Не удалось загрузить отрывок. Проверь подключение.") } }
        }
    }
    func stop(resume: Bool = true) {
        request = UUID(); clearPlayer(); trackID = nil
        if let session { self.session = nil; store?.endTrackPreview(session, resume: resume) }
    }
    private func fail(_ message: String) { stop(); error = message }
    private func clearPlayer() {
        load?.cancel(); load = nil; deadline?.cancel(); deadline = nil; finish?.cancel(); finish = nil
        status = nil; itemStatus = nil
        if let boundary, let player { player.removeTimeObserver(boundary) }; boundary = nil
        player?.pause(); player?.currentItem?.cancelPendingSeeks(); player?.replaceCurrentItem(with: nil); player = nil
        asset?.cancelLoading(); asset = nil; loading = false; playing = false
    }
}

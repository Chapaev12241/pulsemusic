import AVFoundation
import MediaPlayer
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import ImageIO

// The audio clock, queue, system controls and listening history run natively.
final class NativePlayer {
    struct Track {
        let id: String, title: String, artist: String, album: String
        let artwork: URL?
        let url: URL
        init?(_ value: [String: Any]) {
            guard let id = value["id"] as? String, let audio = value["audio"] as? String,
                  let url = URL(string: audio), url.scheme == "https",
                  url.host == "pulse-vibe-music.desyatnichenkoiosyf2.chatgpt.site" else { return nil }
            self.id = id; self.url = url
            title = value["title"] as? String ?? ""; artist = value["artist"] as? String ?? ""
            album = value["album"] as? String ?? ""
            let imageURL = URL(string: value["artwork"] as? String ?? "")
            artwork = imageURL?.scheme == "https" ? imageURL : nil
        }
    }
    var onState: (([String: Any]) -> Void)?
    var onBeat: ((Double) -> Void)?
    var onFavorite: ((String) -> Void)?
    private var favoriteID = ""
    private var favoriteAvailable = false
    private var djTransitions: [String: PulseDJMix] = [:]
    private var currentMix = PulseDJMix(effect: .blend, duration: 3)
    func setDJTransitions(_ values: [String: PulseDJMix]) { djTransitions = values }
    private var queue: [Track] = []
    private var index = 0
    private var player = AVPlayer()
    private var outgoing: AVPlayer?
    private let equalizer = PulseEQController()
    private var observation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var clock: Any?
    private var fade: Timer?
    private var meterTimer: Timer?
    private var notifications: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var dj = true, wantsPlayback = false, fading = false
    private var gain: Float = 0.8
    private var bearer = ""
    private var listened: Double = 0, lastTime: Double = 0
    private var recorded = false
    private var generation = 0
    private var historyTask: URLSessionDataTask?
    #if os(iOS)
    private let session = AVAudioSession.sharedInstance()
    #endif
    private var artworkTask: Task<Void, Never>?
    private var artworkKey: String?
    private var artworkRevision = 0
    private var lastNowPlayingUpdate = 0.0
    private var lastNowPlayingSignature = ""
    private var artworkImage: MPMediaItemArtwork?

    init() {
        let commands = MPRemoteCommandCenter.shared()
        bind(commands.playCommand) { [weak self] in self?.resume() }
        bind(commands.pauseCommand) { [weak self] in self?.pause() }
        bind(commands.nextTrackCommand) { [weak self] in self?.next(1) }
        bind(commands.previousTrackCommand) { [weak self] in self?.next(-1) }
        for command in [commands.likeCommand, commands.bookmarkCommand] {
            command.isEnabled = false
            remoteTargets.append((command, command.addTarget { [weak self] _ in
                DispatchQueue.main.async { _ = self?.toggleFavoriteFromSystem() }
                return .success
            }))
        }
        let seek = commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            DispatchQueue.main.async { self?.seek(event.positionTime) }; return .success
        }
        remoteTargets.append((commands.changePlaybackPositionCommand, seek))
        let center = NotificationCenter.default
        #if os(iOS)
        notifications.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] notification in
            guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            self?.pause() // A call or Siri must never be overridden by an automatic resume.
        })
        notifications.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] notification in
            if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() }
        })
        #endif
        notifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            guard let self = self, let item = notification.object as? AVPlayerItem, item === self.player.currentItem else { return }
            if self.wantsPlayback { self.next(1) }
        })
        #if os(iOS)
        notifications.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.emit(); if self?.wantsPlayback == true { self?.startMeter() } })
        notifications.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.meterTimer?.invalidate(); self?.onBeat?(0) })
        #else
        notifications.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.emit(); if self?.wantsPlayback == true { self?.startMeter() } })
        notifications.append(center.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.meterTimer?.invalidate(); self?.onBeat?(0) })
        #endif
    }
    deinit {
        fade?.invalidate(); meterTimer?.invalidate(); artworkTask?.cancel()
        if let clock = clock { player.removeTimeObserver(clock) }
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        remoteTargets.forEach { $0.0.removeTarget($0.1) }
    }
    private func bind(_ command: MPRemoteCommand, action: @escaping () -> Void) {
        remoteTargets.append((command, command.addTarget { _ in DispatchQueue.main.async { action() }; return .success }))
    }
    func adjacentID(_ direction: Int) -> String? {
        guard !queue.isEmpty else { return nil }
        return queue[(index + direction + queue.count) % queue.count].id
    }
    func setFavoriteState(trackID: String, available: Bool, liked: Bool) {
        favoriteID = trackID; favoriteAvailable = available && !trackID.isEmpty
        for command in [MPRemoteCommandCenter.shared().likeCommand, MPRemoteCommandCenter.shared().bookmarkCommand] {
            command.isEnabled = favoriteAvailable; command.isActive = liked
            command.localizedTitle = liked ? "Убрать из избранного" : "В избранное"
            command.localizedShortTitle = liked ? "В избранном" : "В избранное"
        }
    }
    @discardableResult func toggleFavoriteFromSystem() -> MPRemoteCommandHandlerStatus {
        guard favoriteAvailable, !favoriteID.isEmpty, let onFavorite else { return .noSuchContent }
        onFavorite(favoriteID); return .success
    }
    private func startMeter() {
        meterTimer?.invalidate()
        #if os(iOS)
        guard UIApplication.shared.applicationState == .active else { return }
        #else
        guard NSApplication.shared.isActive else { return }
        #endif
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.onBeat?(self.wantsPlayback && self.player.timeControlStatus == .playing ? self.equalizer.bassLevel : 0)
        }
    }
    func setEqualizer(_ config: PulseEQConfiguration) {
        equalizer.configure(config)
        equalizer.onError = { [weak self] message in self?.emit(error: message) }
        equalizer.attach(to: player.currentItem); equalizer.attach(to: outgoing?.currentItem)
    }
    func command(_ body: [String: Any]) {
        switch body["action"] as? String {
        case "play":
            let items = (body["tracks"] as? [[String: Any]] ?? []).compactMap(Track.init)
            guard let id = body["id"] as? String, let target = items.firstIndex(where: { $0.id == id }) else { return }
            bearer = body["token"] as? String ?? ""
            dj = body["dj"] as? Bool ?? true
            if queue.indices.contains(index), queue[index].id == id, player.currentItem != nil, player.currentItem?.status != .failed {
                queue = items; index = target; resume()
            } else { queue = items; start(target, crossfade: false) }
        case "update":
            bearer = body["token"] as? String ?? ""
            let fresh = Dictionary(uniqueKeysWithValues: (body["tracks"] as? [[String: Any]] ?? []).compactMap(Track.init).map { ($0.id, $0) })
            let currentID = queue.indices.contains(index) ? queue[index].id : ""
            queue = queue.compactMap { fresh[$0.id] }
            if let target = queue.firstIndex(where: { $0.id == currentID }) { index = target }
            else if !currentID.isEmpty { command(["action": "stop"]) }
        case "resume":
            guard queue.indices.contains(index) else { return }
            if player.currentItem?.status == .failed { start(index, crossfade: false) } else { resume() }
        case "pause": pause()
        case "next": next(1)
        case "previous": next(-1)
        case "seek": if let time = body["time"] as? Double { seek(time) }
        case "volume": gain = min(1, max(0, (body["value"] as? NSNumber)?.floatValue ?? 0.8)); if !fading { player.volume = gain }
        case "dj": dj = body["enabled"] as? Bool ?? false; if !dj { finishFade() }
        case "stop": pause(); generation += 1; historyTask?.cancel(); bearer = ""; queue = []; player.replaceCurrentItem(with: nil); emit()
        case "state": emit()
        default: break
        }
    }
    private func activate() throws {
        #if os(iOS)
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try session.setActive(true)
        #endif
    }
    private func resume() {
        guard player.currentItem != nil else { return }
        do { try activate(); wantsPlayback = true; player.play(); startMeter(); emit() }
        catch { emit(error: "Не удалось включить системный звук") }
    }
    private func pause() {
        wantsPlayback = false; player.pause(); finishFade(); meterTimer?.invalidate(); onBeat?(0); emit()
    }
    private func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        finishFade()
        let target = max(0, min(seconds, duration > 0 ? duration : seconds))
        lastTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    private var duration: Double {
        let value = player.currentItem?.duration.seconds ?? 0
        return value.isFinite ? max(0, value) : 0
    }
    private func next(_ direction: Int) {
        guard !queue.isEmpty else { return }
        start((index + direction + queue.count) % queue.count, crossfade: direction > 0 && dj && wantsPlayback)
    }
    private func start(_ target: Int, crossfade: Bool) {
        guard queue.indices.contains(target) else { return }
        do { try activate() } catch { emit(error: "Не удалось включить системный звук"); return }
        finishFade(); observation = nil; itemObservation = nil
        currentMix = djTransitions[queue[target].id] ?? PulseDJMix(effect: .blend, duration: 3)
        if let clock = clock { player.removeTimeObserver(clock); self.clock = nil }
        if crossfade { outgoing = player } else { player.pause() }
        player = AVPlayer(url: queue[target].url)
        equalizer.attach(to: player.currentItem)
        player.automaticallyWaitsToMinimizeStalling = true
        player.currentItem?.preferredForwardBufferDuration = 15
        index = target; listened = 0; lastTime = 0; recorded = false
        wantsPlayback = true; fading = crossfade; player.volume = crossfade ? 0 : gain
        itemObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async {
                self?.pause()
                self?.emit(error: "Трек недоступен. Обнови библиотеку и попробуй ещё раз")
            }
        }
        clock = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in self?.tick() }
        observation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.player.timeControlStatus == .playing && self.fading && self.fade == nil { self.beginFade() }
                if self.player.currentItem?.status == .failed { self.finishFade(); self.emit(error: "Трек недоступен. Обнови библиотеку и попробуй ещё раз") }
                self.emit()
            }
        }
        player.play(); startMeter(); emit()
    }
    private func beginFade() {
        var last = ProcessInfo.processInfo.systemUptime
        var elapsed = 0.0
        fade = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = ProcessInfo.processInfo.systemUptime, delta = min(0.1, max(0, now - last)); last = now
            // Keep the old track audible if the incoming stream has to buffer again.
            guard self.player.timeControlStatus == .playing else { self.outgoing?.volume = self.gain; return }
            elapsed += delta
            let fraction = min(1, elapsed / self.currentMix.duration)
            self.player.volume = self.gain * Float(sin(fraction * .pi / 2))
            self.outgoing?.volume = self.gain * Float(cos(fraction * .pi / 2))
            self.equalizer.transition(item: self.player.currentItem, value: PulseDJFXParameters.values(effect: self.currentMix.effect, progress: fraction, incoming: true))
            self.equalizer.transition(item: self.outgoing?.currentItem, value: PulseDJFXParameters.values(effect: self.currentMix.effect, progress: fraction, incoming: false))
            if fraction >= 1 { self.finishFade() }
        }
    }
    private func finishFade() {
        fade?.invalidate(); fade = nil; outgoing?.pause(); outgoing = nil
        fading = false; player.volume = gain
        equalizer.resetTransition()
    }
    private func tick() {
        let time = player.currentTime().seconds
        if time.isFinite {
            let delta = time - lastTime
            if player.timeControlStatus == .playing && delta > 0 && delta < 1 { listened += delta }
            lastTime = time
            if !recorded && duration > 0 && listened >= min(30, duration / 2) { saveHistory() }
            let nextID = adjacentID(1) ?? ""
            let transitionDuration = djTransitions[nextID]?.duration ?? 3
            if wantsPlayback && dj && !fading && duration > 20 && duration - time <= transitionDuration + 0.8 && duration - time > 0 && queue.count > 1 { next(1); return }
        }
        emit()
    }
    private func saveHistory() {
        guard !bearer.isEmpty, queue.indices.contains(index) else { return }
        recorded = true
        let trackID = queue[index].id, sessionGeneration = generation
        var request = URLRequest(url: URL(string: "https://pulse-vibe-music.desyatnichenkoiosyf2.chatgpt.site/api/state")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["op": ["type": "history", "id": trackID]])
        historyTask = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self = self, self.generation == sessionGeneration else { return }
                if error != nil || (response as? HTTPURLResponse)?.statusCode != 200 {
                    self.emit(error: "История не синхронизирована — проверь сеть")
                } else { self.onState?(["historySaved": true]) }
            }
        }
        historyTask?.resume()
    }
    private func loadArtwork(_ track: Track?) {
        let key = track.map { $0.id + "|" + ($0.artwork?.absoluteString ?? "") }
        guard artworkKey != key else { return }
        artworkTask?.cancel(); artworkKey = key; artworkImage = nil; artworkRevision += 1
        guard let track else { return }
        if let url = Bundle.main.url(forResource: "now-playing-fallback", withExtension: "png"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512] as CFDictionary) {
            artworkImage = Self.systemArtwork(image)
        }
        let value = PulseTrack(id: track.id, title: track.title, artist: track.artist, album: track.album, genres: nil, artwork: track.artwork?.absoluteString, audio: track.url.absoluteString)
        artworkTask = Task { @MainActor [weak self] in
            let image = await PulseArtworkCache.shared.image(for: value)
            guard let self, !Task.isCancelled, self.artworkKey == key, let image else { return }
            self.artworkImage = Self.systemArtwork(image); self.artworkRevision += 1; self.emit()
        }
    }
    private static func systemArtwork(_ cg: CGImage) -> MPMediaItemArtwork {
        #if os(iOS)
        let image = UIImage(cgImage: cg)
        #else
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        #endif
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
    private func emit(error: String? = nil) {
        let seconds = player.currentTime().seconds
        let playing = wantsPlayback && player.currentItem != nil
        let track = queue.indices.contains(index) ? queue[index] : nil
        var result: [String: Any] = ["id": track?.id ?? "", "time": seconds.isFinite ? seconds : 0, "duration": duration, "paused": !playing, "buffering": playing && player.timeControlStatus != .playing]
        result["equalizerActive"] = equalizer.hasProcessedAudio && playing && player.rate > 0
        if let error = error { result["error"] = error }
        if let track = track {
            loadArtwork(track)
            var info: [String: Any] = [MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist, MPMediaItemPropertyAlbumTitle: track.album, MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: seconds.isFinite ? seconds : 0, MPNowPlayingInfoPropertyPlaybackRate: player.rate]
            if let artworkImage = artworkImage { info[MPMediaItemPropertyArtwork] = artworkImage }
            info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
            info[MPNowPlayingInfoPropertyIsLiveStream] = false
            info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
            info[MPNowPlayingInfoPropertyExternalContentIdentifier] = track.id
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = queue.count
            let signature = track.id + "|" + String(player.rate) + "|" + String(artworkRevision)
            let now = ProcessInfo.processInfo.systemUptime
            if signature != lastNowPlayingSignature || now - lastNowPlayingUpdate >= 1 {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                lastNowPlayingSignature = signature; lastNowPlayingUpdate = now
                #if os(macOS)
                MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
                #endif
            }
        } else { loadArtwork(nil); MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; lastNowPlayingSignature = "" }
        onState?(result)
    }
}

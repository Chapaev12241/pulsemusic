import AVFoundation
import MediaPlayer
import UIKit
import ImageIO

// The audio clock and queue live outside WKWebView, including when WebKit is suspended.
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
    private var queue: [Track] = []
    private var index = 0
    private var player = AVPlayer()
    private var outgoing: AVPlayer?
    private var observation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var clock: Any?
    private var fade: Timer?
    private var notifications: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var dj = true, wantsPlayback = false, fading = false
    private var gain: Float = 0.8
    private var bearer = ""
    private var listened: Double = 0, lastTime: Double = 0
    private var recorded = false
    private var generation = 0
    private var historyTask: URLSessionDataTask?
    private let session = AVAudioSession.sharedInstance()
    private var artworkTask: URLSessionDataTask?
    private var artworkURL: URL?
    private var artworkImage: MPMediaItemArtwork?

    init() {
        let commands = MPRemoteCommandCenter.shared()
        bind(commands.playCommand) { [weak self] in self?.resume() }
        bind(commands.pauseCommand) { [weak self] in self?.pause() }
        bind(commands.nextTrackCommand) { [weak self] in self?.next(1) }
        bind(commands.previousTrackCommand) { [weak self] in self?.next(-1) }
        let seek = commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(event.positionTime); return .success
        }
        remoteTargets.append((commands.changePlaybackPositionCommand, seek))
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] notification in
            guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            self?.pause() // A call or Siri must never be overridden by an automatic resume.
        })
        notifications.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] notification in
            if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() }
        })
        notifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            guard let self = self, let item = notification.object as? AVPlayerItem, item === self.player.currentItem else { return }
            if self.wantsPlayback { self.next(1) }
        })
        notifications.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.emit() })
    }
    deinit {
        fade?.invalidate(); artworkTask?.cancel()
        if let clock = clock { player.removeTimeObserver(clock) }
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        remoteTargets.forEach { $0.0.removeTarget($0.1) }
    }
    private func bind(_ command: MPRemoteCommand, action: @escaping () -> Void) {
        remoteTargets.append((command, command.addTarget { _ in action(); return .success }))
    }
    func command(_ body: [String: Any]) {
        switch body["action"] as? String {
        case "play":
            let items = (body["tracks"] as? [[String: Any]] ?? []).compactMap(Track.init)
            guard let id = body["id"] as? String, let target = items.firstIndex(where: { $0.id == id }) else { return }
            bearer = body["token"] as? String ?? ""
            dj = body["dj"] as? Bool ?? true
            if queue.indices.contains(index), queue[index].id == id, player.currentItem != nil {
                queue = items; index = target; resume()
            } else { queue = items; start(target, crossfade: false) }
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
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try session.setActive(true)
    }
    private func resume() {
        guard player.currentItem != nil else { return }
        do { try activate(); wantsPlayback = true; player.play(); emit() }
        catch { emit(error: "Не удалось включить системный звук") }
    }
    private func pause() {
        wantsPlayback = false; player.pause(); finishFade(); emit()
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
        if let clock = clock { player.removeTimeObserver(clock); self.clock = nil }
        if crossfade { outgoing = player } else { player.pause() }
        player = AVPlayer(url: queue[target].url)
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
        player.play(); emit()
    }
    private func beginFade() {
        let start = ProcessInfo.processInfo.systemUptime
        fade = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Keep the old track audible if the incoming stream has to buffer again.
            guard self.player.timeControlStatus == .playing else { self.outgoing?.volume = self.gain; return }
            let fraction = min(1, (ProcessInfo.processInfo.systemUptime - start) / 3)
            self.player.volume = self.gain * Float(sin(fraction * .pi / 2))
            self.outgoing?.volume = self.gain * Float(cos(fraction * .pi / 2))
            if fraction >= 1 { self.finishFade() }
        }
    }
    private func finishFade() {
        fade?.invalidate(); fade = nil; outgoing?.pause(); outgoing = nil
        fading = false; player.volume = gain
    }
    private func tick() {
        let time = player.currentTime().seconds
        if time.isFinite {
            let delta = time - lastTime
            if player.timeControlStatus == .playing && delta > 0 && delta < 1 { listened += delta }
            lastTime = time
            if !recorded && duration > 0 && listened >= min(30, duration / 2) { saveHistory() }
            if wantsPlayback && dj && !fading && duration > 20 && duration - time <= 3.5 && duration - time > 0 && queue.count > 1 { next(1); return }
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
    private func loadArtwork(_ url: URL?) {
        guard artworkURL != url else { return }
        artworkTask?.cancel(); artworkURL = url; artworkImage = nil
        guard let url = url else { return }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        artworkTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let data = data, data.count <= 5_000_000, (response as? HTTPURLResponse)?.statusCode == 200,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 600] as CFDictionary) else { return }
            let image = UIImage(cgImage: cg)
            DispatchQueue.main.async {
                guard let self = self, self.artworkURL == url else { return }
                self.artworkImage = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.emit()
            }
        }
        artworkTask?.resume()
    }
    private func emit(error: String? = nil) {
        let seconds = player.currentTime().seconds
        let playing = wantsPlayback && player.currentItem != nil
        let track = queue.indices.contains(index) ? queue[index] : nil
        var result: [String: Any] = ["id": track?.id ?? "", "time": seconds.isFinite ? seconds : 0, "duration": duration, "paused": !playing, "buffering": playing && player.timeControlStatus != .playing]
        if let error = error { result["error"] = error }
        if let track = track {
            loadArtwork(track.artwork)
            var info: [String: Any] = [MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist, MPMediaItemPropertyAlbumTitle: track.album, MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: seconds.isFinite ? seconds : 0, MPNowPlayingInfoPropertyPlaybackRate: player.rate]
            if let artworkImage = artworkImage { info[MPMediaItemPropertyArtwork] = artworkImage }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        } else { loadArtwork(nil); MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        onState?(result)
    }
}

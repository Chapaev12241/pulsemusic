import SwiftUI
import CryptoKit
import AVFoundation
import Combine

@MainActor
final class PulseStore: ObservableObject {
    @Published var user: PulseUser?
    @Published var tracks: [PulseTrack] = []
    @Published var ownedIDs = Set<String>()
    @Published var state = PulseLibraryState()
    @Published var error: String?
    @Published var syncing = false
    @Published var authenticating = false
    @Published var uploading = false
    @Published var uploadStatus = ""
    @Published var lastSync: Date?
    @Published var currentID = ""
    @Published var paused = true
    let playback = PulsePlayback()
    let social = PulseSocialStore()
    let equalizer = PulseEqualizerSettings()
    let beat = PulseBeat()
    let djLibrary = PulseDJStore()
    let ai = PulseAIStore()
    let downloads = PulseDownloads()
    private var equalizerSubscription: AnyCancellable?
    private var favoriteSubscription: AnyCancellable?
    private var downloadSubscription: AnyCancellable?
    @Published var shuffle = UserDefaults.standard.bool(forKey: "pulse_shuffle") {
        didSet { UserDefaults.standard.set(shuffle, forKey: "pulse_shuffle"); player.command(["action": "shuffle", "enabled": shuffle]) }
    }
    @Published var dj = UserDefaults.standard.object(forKey: "pulse_dj_native") as? Bool ?? true {
        didSet { UserDefaults.standard.set(dj, forKey: "pulse_dj_native"); player.command(["action": "dj", "enabled": dj]) }
    }
    @Published var volume = min(1, max(0, UserDefaults.standard.object(forKey: "pulse_native_volume") as? Double ?? 0.8)) {
        didSet { UserDefaults.standard.set(volume, forKey: "pulse_native_volume"); player.command(["action": "volume", "value": volume]) }
    }
    private var token = ""
    private let loadSession: () async -> String
    private var keychainCleanup: Task<Void, Never>?
    private var generation = UUID()
    private var publicTracks: [PulseTrack] = []
    private var ownedTracks: [PulseTrack] = []
    private var mutation: Task<Void, Never>?
    private var mutating = false
    private var stateRevision = 0
    private var started = false
    private let player = NativePlayer()
    var currentTrack: PulseTrack? { tracks.first { $0.id == currentID } }
    var signedIn: Bool { user != nil }
    func adjacentTrack(_ direction: Int) -> PulseTrack? {
        guard let id = player.adjacentID(direction) else { return nil }
        return tracks.first { $0.id == id }
    }

    init(loadSession: @escaping () async -> String = {
        await Task.detached(priority: .userInitiated) { PulseKeychain.load() }.value
    }) {
        self.loadSession = loadSession
        tracks = downloads.tracks
        downloadSubscription = downloads.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        player.onState = { [weak self] value in self?.receivePlayback(value) }
        player.onBeat = { [weak self] value in self?.beat.receive(value) }
        player.onFavorite = { [weak self] id in
            guard let self, let track = self.tracks.first(where: { $0.id == id }), self.signedIn else { return }
            self.like(track)
        }
        player.command(["action": "volume", "value": volume])
        player.command(["action": "shuffle", "enabled": shuffle])
        equalizerSubscription = equalizer.$config.sink { [weak self] value in self?.player.setEqualizer(value) }
        favoriteSubscription = Publishers.CombineLatest3($currentID, $user, $state).sink { [weak self] id, user, state in
            self?.player.setFavoriteState(trackID: id, available: user != nil, liked: state.liked.contains(id))
        }
    }
    // NativePlayer delivers callbacks on the main queue. This boundary is also
    // exercised by the regression test for library invalidations.
    func receivePlayback(_ value: [String: Any]) {
        if value["historySaved"] as? Bool == true { Task { await self.refresh() }; return }
        if let message = value["error"] as? String { error = message; return }
        playback.receive(value)
        let id = value["id"] as? String ?? ""
        let nextPaused = value["paused"] as? Bool ?? true
        if currentID != id { currentID = id }
        if paused != nextPaused { paused = nextPaused }
    }
    func start() async {
        if !started { started = true; await restore() }
        while !Task.isCancelled {
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            await refresh()
        }
    }
    func restore() async {
        let readStamp = generation
        let restoredToken = await loadSession()
        guard generation == readStamp, !Task.isCancelled else { return }
        token = restoredToken
        if !restoredToken.isEmpty { generation = UUID() }
        let stamp = generation
        if !token.isEmpty {
            do {
                let identity: PulseIdentity = try await PulseAPI.request("api/auth/me", token: token)
                guard generation == stamp else { return }
                if identity.authenticated { user = identity.user }
                else { clearSession() }
            } catch { if generation == stamp && !Task.isCancelled { self.error = "Не удалось восстановить вход: \(error.localizedDescription)" } }
        }
        guard generation == stamp, !Task.isCancelled else { return }
        configureSocial()
        await refresh()
    }
    func signIn(email: String, password: String, name: String, register: Bool) async -> Bool {
        guard !authenticating else { return false }
        authenticating = true
        defer { authenticating = false }
        do {
            let session: PulseSession = try await PulseAPI.request(register ? "api/auth/register" : "api/auth/login", method: "POST", body: PulseAPI.json(["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password, "name": name]))
            await keychainCleanup?.value
            try await Task.detached(priority: .userInitiated) { try PulseKeychain.save(session.token) }.value
            clearSession(deleteKeychain: false)
            token = session.token; user = session.user
            configureSocial()
            error = nil
            await refresh()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func logout() async {
        guard !uploading else { error = "Дождись окончания загрузки"; return }
        let oldToken = token
        clearSession()
        // Clear locally first, including on a failed network request.
        let _: PulseOK? = try? await PulseAPI.request("api/auth/logout", token: oldToken, method: "POST")
        await refresh()
    }
    private func clearSession(deleteKeychain: Bool = true) {
        djLibrary.clear(); ai.configure(owner: "guest")
        generation = UUID(); mutation?.cancel(); mutation = nil
        player.command(["action": "stop"])
        token = ""; user = nil; social.configure(token: "", userID: ""); ownedTracks = []; ownedIDs = []; state = PulseLibraryState()
        tracks = publicTracks; lastSync = nil
        if deleteKeychain {
            let previous = keychainCleanup
            keychainCleanup = Task.detached(priority: .userInitiated) { await previous?.value; PulseKeychain.clear() }
        }
    }
    func refresh() async {
        guard !syncing, !mutating else { return }
        syncing = true
        let stamp = generation, sessionToken = token, revision = stateRevision
        defer {
            syncing = false
            if stamp != generation { Task { await self.refresh() } }
        }
        do {
            let catalog: PulseCatalog = try await PulseAPI.request("api/catalog")
            guard stamp == generation else { return }
            publicTracks = catalog.tracks
            if !sessionToken.isEmpty {
                async let music: PulseCatalog = PulseAPI.request("api/music", token: sessionToken)
                async let saved: PulseLibraryState = PulseAPI.request("api/state", token: sessionToken)
                let (library, remoteState) = try await (music, saved)
                guard stamp == generation else { return }
                ownedTracks = library.tracks
                let freshIDs = Set(library.tracks.map(\.id))
                if ownedIDs != freshIDs { ownedIDs = freshIDs }
                if revision == stateRevision && state != remoteState { state = remoteState }
                // Retry identity after a transient restore failure without discarding the token.
                if user == nil {
                    let identity: PulseIdentity = try await PulseAPI.request("api/auth/me", token: sessionToken)
                    guard stamp == generation else { return }
                    user = identity.user
                }
            }
            let merged = PulseLibrary.merge(publicTracks: publicTracks, ownedTracks: ownedTracks)
            if tracks != merged { tracks = merged }
            lastSync = Date()
            configureSocial()
            Task { await self.social.refresh() }
            if !currentID.isEmpty {
                if currentTrack == nil { player.command(["action": "stop"]) }
                else { player.command(["action": "update", "token": token, "tracks": tracks.map(\.nativeValue)]) }
            }
        } catch {
            guard stamp == generation else { return }
            if let api = error as? PulseAPIError, api.status == 401 {
                clearSession(); self.error = "Сессия закончилась. Войди снова."
            } else {
                tracks = PulseLibrary.merge(publicTracks: publicTracks, ownedTracks: ownedTracks + downloads.tracks)
                if tracks.isEmpty { self.error = "Медиатека не обновлена: \(error.localizedDescription)" }
            }
        }
    }
    private func configureSocial() { ai.configure(owner: user?.id ?? "guest"); social.configure(token: token, userID: user?.id ?? ""); djLibrary.configure(owner: user?.id ?? "guest") }
    func playWave() {
        let liked = Set(state.liked)
        let artists = Set(tracks.filter { liked.contains($0.id) }.map(\.artist))
        let recent = Set(state.history.prefix(20).map(\.id))
        let shuffled = tracks.shuffled()
        let familiar = shuffled.filter { artists.contains($0.artist) && !recent.contains($0.id) }
        let discovery = shuffled.filter { !artists.contains($0.artist) && !recent.contains($0.id) }
        var queue: [PulseTrack] = []
        for i in 0..<max(familiar.count, discovery.count) {
            if familiar.indices.contains(i) { queue.append(familiar[i]) }
            if discovery.indices.contains(i) { queue.append(discovery[i]) }
        }
        queue += shuffled.filter { recent.contains($0.id) }
        if let first = queue.first { play(first, within: queue) }
    }
    func setPlaylistCover(_ id: String, url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try await Task.detached(priority: .userInitiated) { try PulseCoverCodec.encode(url) }.value
            mutate(["type": "playlistCover", "id": id, "cover": "data:image/jpeg;base64," + data.base64EncodedString()])
        } catch { self.error = error.localizedDescription }
    }
    func play(_ track: PulseTrack, within queue: [PulseTrack]) {
        player.setDJTransitions([:])
        player.command(["action": "play", "id": track.id, "tracks": queue.map(\.nativeValue), "token": token, "dj": dj])
    }
    func playDJ(_ track: PulseTrack, within queue: [PulseTrack], transitions: [String: PulseDJMix]) {
        dj = true; player.setDJTransitions(transitions)
        player.command(["action": "play", "id": track.id, "tracks": queue.map(\.nativeValue), "token": token, "dj": true])
    }
    func togglePlayback() {
        player.command(["action": paused ? "resume" : "pause"])
    }
    func next(_ direction: Int) { PulseHaptics.fire(.track); player.command(["action": direction > 0 ? "next" : "previous"]) }
    func seek(_ seconds: Double) { player.command(["action": "seek", "time": seconds]) }
    func like(_ track: PulseTrack) { mutate(["type": "like", "id": track.id, "value": !state.liked.contains(track.id)]) }
    func createPlaylist(_ name: String) { mutate(["type": "playlist", "id": UUID().uuidString, "name": name]) }
    func add(_ track: PulseTrack, to playlist: PulsePlaylist) { mutate(["type": "add", "id": track.id, "playlist": playlist.id]) }
    private func mutate(_ operation: [String: Any]) {
        guard signedIn else { error = "Войди в аккаунт, чтобы сохранить музыку"; return }
        stateRevision += 1
        let previous = mutation, stamp = generation, sessionToken = token
        mutation = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, self.generation == stamp else { return }
            self.mutating = true
            defer { self.mutating = false }
            do {
                let saved: PulseLibraryState = try await PulseAPI.request("api/state", token: sessionToken, method: "POST", body: PulseAPI.json(["op": operation]))
                guard self.generation == stamp else { return }
                self.stateRevision += 1
                self.state = saved
            } catch { if self.generation == stamp { self.error = error.localizedDescription } }
        }
    }
    func saveAIPlaylist(_ draft: PulseAIDraft) async -> Bool {
        guard signedIn else { error = "Войди в аккаунт, чтобы сохранить плейлист"; return false }
        let available = Set(tracks.map(\.id)), ids = draft.tracks.filter { available.contains($0) }
        guard !ids.isEmpty else { error = "Треки этой подборки больше недоступны"; return false }
        mutate(["type": "playlist", "id": draft.id, "name": String(draft.name.prefix(80)), "tracks": ids])
        await mutation?.value
        return state.playlists.contains { $0.id == draft.id }
    }
    func importFiles(_ urls: [URL]) async {
        guard signedIn, !uploading else { error = "Войди в аккаунт перед импортом"; return }
        uploading = true
        defer { uploading = false }
        let sessionToken = token, stamp = generation
        var added = 0, duplicates = 0, failed: [String] = []
        let types = ["mp3": "audio/mpeg", "m4a": "audio/mp4", "aac": "audio/aac", "wav": "audio/wav", "flac": "audio/flac", "ogg": "audio/ogg", "opus": "audio/ogg"]
        for (index, url) in urls.enumerated() {
            guard generation == stamp else { return }
            uploadStatus = "\(index + 1) / \(urls.count) · \(url.lastPathComponent)"
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                guard let type = types[url.pathExtension.lowercased()] else { throw PulseAPIError(status: 415, message: "Неподдерживаемый формат") }
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 50 * 1024 * 1024 else { throw PulseAPIError(status: 413, message: "Размер файла должен быть от 1 байта до 50 МБ") }
                let (data, id) = try await Task.detached(priority: .userInitiated) {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    let id = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    return (data, id)
                }.value
                let metadata = await Self.metadata(url)
                let name = url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "track"
                let encodedMetadata = String(data: try PulseAPI.json(metadata), encoding: .utf8)!.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
                let result: PulseUpload = try await PulseAPI.request("api/music/\(id)", token: sessionToken, method: "POST", body: data, headers: ["Content-Type": type, "X-File-Name": name, "X-Track-Metadata": encodedMetadata])
                if result.duplicate == true { duplicates += 1 } else { added += 1 }
            } catch { failed.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        uploadStatus = "Загружено: \(added) · Уже есть: \(duplicates) · Ошибок: \(failed.count)"
        if !failed.isEmpty { error = failed.joined(separator: "\n") }
        await refresh()
    }
    private static func metadata(_ url: URL) async -> [String: Any] {
        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        var tags: [String: Any] = [:]
        for item in metadata {
            guard let key = item.commonKey?.rawValue, ["title", "artist", "albumName"].contains(key), let value = try? await item.load(.stringValue) else { continue }
            tags[key == "albumName" ? "album" : key] = value
        }
        if tags["title"] == nil {
            let parts = url.deletingPathExtension().lastPathComponent.components(separatedBy: " - ")
            tags["title"] = parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : parts[0]
            if tags["artist"] == nil { tags["artist"] = parts.count > 1 ? parts[0] : "Моя коллекция" }
        }
        return tags
    }
}

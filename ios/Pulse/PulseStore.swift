import SwiftUI
import CryptoKit
import AVFoundation

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
    @Published var buffering = false
    @Published var time = 0.0
    @Published var duration = 0.0
    @Published var dj = UserDefaults.standard.object(forKey: "pulse_dj_native") as? Bool ?? true {
        didSet { UserDefaults.standard.set(dj, forKey: "pulse_dj_native"); player.command(["action": "dj", "enabled": dj]) }
    }
    @Published var volume = 0.8 {
        didSet { player.command(["action": "volume", "value": volume]) }
    }
    private var token = PulseKeychain.load()
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

    init() {
        player.onState = { [weak self] value in
            // NativePlayer delivers callbacks on the main queue.
            guard let self else { return }
            if value["historySaved"] as? Bool == true { Task { await self.refresh() }; return }
            if let message = value["error"] as? String { self.error = message; return }
            self.currentID = value["id"] as? String ?? ""
            self.paused = value["paused"] as? Bool ?? true
            self.buffering = value["buffering"] as? Bool ?? false
            self.time = value["time"] as? Double ?? 0
            self.duration = value["duration"] as? Double ?? 0
        }
    }
    func start() async {
        if !started { started = true; await restore() }
        while !Task.isCancelled {
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            await refresh()
        }
    }
    func restore() async {
        let stamp = generation
        if !token.isEmpty {
            do {
                let identity: PulseIdentity = try await PulseAPI.request("api/auth/me", token: token)
                guard generation == stamp else { return }
                if identity.authenticated { user = identity.user }
                else { clearSession() }
            } catch { self.error = "Не удалось восстановить вход: \(error.localizedDescription)" }
        }
        await refresh()
    }
    func signIn(email: String, password: String, name: String, register: Bool) async -> Bool {
        guard !authenticating else { return false }
        authenticating = true
        defer { authenticating = false }
        do {
            let session: PulseSession = try await PulseAPI.request(register ? "api/auth/register" : "api/auth/login", method: "POST", body: PulseAPI.json(["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password, "name": name]))
            try PulseKeychain.save(session.token)
            clearSession(deleteKeychain: false)
            token = session.token; user = session.user
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
        generation = UUID(); mutation?.cancel(); mutation = nil
        player.command(["action": "stop"])
        token = ""; user = nil; ownedTracks = []; ownedIDs = []; state = PulseLibraryState()
        tracks = publicTracks; lastSync = nil
        if deleteKeychain { PulseKeychain.clear() }
    }
    func refresh() async {
        guard !syncing, !mutating else { return }
        syncing = true
        defer { syncing = false }
        let stamp = generation, sessionToken = token, revision = stateRevision
        do {
            let catalog: PulseCatalog = try await PulseAPI.request("api/catalog")
            guard stamp == generation else { return }
            publicTracks = catalog.tracks
            if !sessionToken.isEmpty {
                async let music: PulseCatalog = PulseAPI.request("api/music", token: sessionToken)
                async let saved: PulseLibraryState = PulseAPI.request("api/state", token: sessionToken)
                let (library, remoteState) = try await (music, saved)
                guard stamp == generation else { return }
                ownedTracks = library.tracks; ownedIDs = Set(library.tracks.map(\.id)); if revision == stateRevision { state = remoteState }
                // Retry identity after a transient restore failure without discarding the token.
                if user == nil {
                    let identity: PulseIdentity = try await PulseAPI.request("api/auth/me", token: sessionToken)
                    guard stamp == generation else { return }
                    user = identity.user
                }
            }
            tracks = PulseLibrary.merge(publicTracks: publicTracks, ownedTracks: ownedTracks)
            lastSync = Date()
            if !currentID.isEmpty {
                if currentTrack == nil { player.command(["action": "stop"]) }
                else { player.command(["action": "update", "token": token, "tracks": tracks.map(\.nativeValue)]) }
            }
        } catch {
            guard stamp == generation else { return }
            if let api = error as? PulseAPIError, api.status == 401 {
                clearSession(); self.error = "Сессия закончилась. Войди снова."
            } else {
                tracks = PulseLibrary.merge(publicTracks: publicTracks, ownedTracks: ownedTracks)
                self.error = "Медиатека не обновлена: \(error.localizedDescription)"
            }
        }
    }
    func play(_ track: PulseTrack, within queue: [PulseTrack]) {
        player.command(["action": "play", "id": track.id, "tracks": queue.map(\.nativeValue), "token": token, "dj": dj])
    }
    func togglePlayback() {
        player.command(["action": paused ? "resume" : "pause"])
    }
    func next(_ direction: Int) { player.command(["action": direction > 0 ? "next" : "previous"]) }
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
                self.state = saved
            } catch { if self.generation == stamp { self.error = error.localizedDescription } }
        }
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
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let id = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

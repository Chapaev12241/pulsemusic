import SwiftUI
import ImageIO
import CryptoKit
import UniformTypeIdentifiers
import Network

@MainActor
final class PulseDownloads: ObservableObject {
    @Published private(set) var tracks: [PulseTrack] = []
    @Published private(set) var cachedTracks: [PulseTrack] = []
    @Published private(set) var isOffline = false
    private let network = NWPathMonitor()
    private var artworkBackfill: Task<Void, Never>?
    var offlineTracks: [PulseTrack] {
        var seen = Set<String>()
        return (tracks + cachedTracks).filter { Self.localURL($0.id) != nil && seen.insert($0.id).inserted }
    }
    @Published private(set) var pending = Set<String>()
    @Published var error: String?
    private var queued: [PulseTrack] = []
    private var running: [String: Task<Void, Never>] = [:]
    private var persistent = Set<String>()
    private var wanted = Set<String>()
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pulse/Downloads", isDirectory: true)
    }
    nonisolated static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Pulse/Audio", isDirectory: true)
    }
    nonisolated private static func file(_ id: String, in folder: URL) -> URL? {
        guard id.count == 64, id.allSatisfy({ $0.isHexDigit }) else { return nil }
        for ext in ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"] {
            let url = folder.appendingPathComponent(id + "." + ext)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
    nonisolated static func savedURL(_ id: String) -> URL? { file(id, in: directory) }
    nonisolated static func localURL(_ id: String) -> URL? { savedURL(id) ?? file(id, in: cacheDirectory) }
    init() {
        if let data = try? Data(contentsOf: Self.directory.appendingPathComponent("index.json")), let saved = try? JSONDecoder().decode([PulseTrack].self, from: data) { tracks = saved.filter { Self.savedURL($0.id) != nil } }
        if let data = try? Data(contentsOf: Self.cacheDirectory.appendingPathComponent("index.json")), let saved = try? JSONDecoder().decode([PulseTrack].self, from: data) { cachedTracks = saved.filter { Self.localURL($0.id) != nil } }
        network.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isOffline != offline { self.isOffline = offline }
                if offline { self.stopPreloading() } else { self.backfillArtwork(); self.pump() }
            }
        }
        network.start(queue: DispatchQueue(label: "pulse.connectivity", qos: .utility))
    }
    deinit { network.cancel(); artworkBackfill?.cancel() }
    private func backfillArtwork() {
        artworkBackfill?.cancel()
        let values = offlineTracks
        artworkBackfill = Task {
            for track in values {
                if Task.isCancelled { return }
                await PulseArtworkCache.shared.retainOffline(track)
            }
        }
    }
    // Keep just two transfers active. Explicit downloads take priority over speculative caching.
    func download(_ track: PulseTrack) async { downloadAll([track]) }
    func downloadAll(_ values: [PulseTrack]) {
        for track in values where Self.savedURL(track.id) == nil {
            guard valid(track) else { continue }
            persistent.insert(track.id); pending.insert(track.id)
            if running[track.id] == nil && !queued.contains(where: { $0.id == track.id }) { queued.append(track) }
        }
        queued.sort { persistent.contains($0.id) && !persistent.contains($1.id) }
        pump()
    }
    func preload(_ values: [PulseTrack], after id: String) {
        guard !isOffline else { stopPreloading(); return }
        let index = values.firstIndex { $0.id == id } ?? 0
        let ordered = Array(values.dropFirst(index + 1)) + Array(values.prefix(index + 1))
        wanted = Set(values.map(\.id))
        queued.removeAll { !persistent.contains($0.id) }
        var added = Set(queued.map(\.id))
        for track in ordered where Self.localURL(track.id) == nil && running[track.id] == nil && added.insert(track.id).inserted && valid(track) { queued.append(track) }
        pump()
    }
    func stopPreloading() {
        wanted = []; queued.removeAll { !persistent.contains($0.id) }
    }
    private func valid(_ track: PulseTrack) -> Bool {
        track.id.count == 64 && track.id.allSatisfy { $0.isHexDigit } && URL(string: track.audio).map { $0.scheme == "https" && $0.host == PulseAPI.base.host } == true
    }
    private func pump() {
        while running.count < 2, !queued.isEmpty {
            let position: Int
            if isOffline {
                guard let cached = queued.firstIndex(where: { Self.localURL($0.id) != nil }) else { return }
                position = cached
            } else { position = 0 }
            let track = queued.remove(at: position)
            guard running[track.id] == nil else { continue }
            running[track.id] = Task { [weak self] in
                guard let self else { return }
                defer { self.running[track.id] = nil; self.pending.remove(track.id); self.persistent.remove(track.id); self.pump() }
                do {
                    try await self.save(track)
                    if Self.localURL(track.id) != nil { await PulseArtworkCache.shared.retainOffline(track) }
                }
                catch { if !Task.isCancelled && self.persistent.contains(track.id) { self.error = "Не удалось скачать «\(track.title)»: " + error.localizedDescription } }
            }
        }
    }
    private func save(_ track: PulseTrack) async throws {
        if Self.savedURL(track.id) != nil { return }
        if let cached = Self.localURL(track.id) {
            if persistent.contains(track.id) { try retain(track, file: cached, ext: cached.pathExtension) }
            return
        }
        guard let url = URL(string: track.audio) else { return }
        var request = URLRequest(url: url)
        request.networkServiceType = persistent.contains(track.id) ? .default : .background
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.mimeType?.hasPrefix("audio/") == true else { throw URLError(.badServerResponse) }
        let formats = ["audio/mpeg": "mp3", "audio/mp3": "mp3", "audio/mp4": "m4a", "audio/x-m4a": "m4a", "audio/aac": "aac", "audio/wav": "wav", "audio/x-wav": "wav", "audio/flac": "flac", "audio/ogg": "ogg", "audio/opus": "opus"]
        guard let ext = formats[http.mimeType ?? ""], (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else { throw URLError(.cannotDecodeContentData) }
        if persistent.contains(track.id) { try retain(track, file: temporary, ext: ext) }
        else if wanted.contains(track.id) {
            try FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
            let destination = Self.cacheDirectory.appendingPathComponent(track.id + "." + ext)
            if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.moveItem(at: temporary, to: destination) }
            if !cachedTracks.contains(where: { $0.id == track.id }) { cachedTracks.append(track) }
            pruneCache()
            try persistCache()
        }
    }
    private func retain(_ track: PulseTrack, file: URL, ext: String) throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        var folder = Self.directory; var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try? folder.setResourceValues(flags)
        let target = Self.directory.appendingPathComponent(track.id + "." + ext)
        if !FileManager.default.fileExists(atPath: target.path) {
            if file.deletingLastPathComponent() == Self.cacheDirectory { try FileManager.default.copyItem(at: file, to: target) }
            else { try FileManager.default.moveItem(at: file, to: target) }
        }
        if !tracks.contains(where: { $0.id == track.id }) { tracks.append(track) }
        try persist()
    }
    private func pruneCache() {
        // Evict older queues, never the active playlist or explicit offline downloads.
        guard let files = try? FileManager.default.contentsOfDirectory(at: Self.cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        let sizes = files.filter { $0.pathExtension != "json" }.map { ($0, (try? $0.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]))) }
        var size = sizes.reduce(0) { $0 + ($1.1?.fileSize ?? 0) }
        for (url, info) in sizes.sorted(by: { ($0.1?.contentModificationDate ?? .distantPast) < ($1.1?.contentModificationDate ?? .distantPast) }) where size > 512 * 1024 * 1024 && !wanted.contains(url.deletingPathExtension().lastPathComponent) {
            if (try? FileManager.default.removeItem(at: url)) != nil { size -= info?.fileSize ?? 0 }
        }
        cachedTracks.removeAll { Self.localURL($0.id) == nil }
    }
    private func persistCache() throws {
        try JSONEncoder().encode(cachedTracks).write(to: Self.cacheDirectory.appendingPathComponent("index.json"), options: .atomic)
    }
    func remove(_ track: PulseTrack) {
        running[track.id]?.cancel(); queued.removeAll { $0.id == track.id }; persistent.remove(track.id); pending.remove(track.id)
        do { if let url = Self.savedURL(track.id) { try FileManager.default.removeItem(at: url) }; tracks.removeAll { $0.id == track.id }; try persist() }
        catch { self.error = error.localizedDescription }
    }
    private func persist() throws { try JSONEncoder().encode(tracks).write(to: Self.directory.appendingPathComponent("index.json"), options: .atomic) }
}
struct PulsePlaylistDownloadButton: View {
    let tracks: [PulseTrack]
    @ObservedObject var downloads: PulseDownloads
    private var savedCount: Int { let ids = Set(downloads.tracks.map(\.id)); return tracks.filter { ids.contains($0.id) }.count }
    private var busy: Bool { tracks.contains { downloads.pending.contains($0.id) } }
    private var complete: Bool { !tracks.isEmpty && savedCount == tracks.count }
    var body: some View {
        Button { downloads.downloadAll(tracks) } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small) }
                else { Image(systemName: complete ? "checkmark.circle.fill" : "arrow.down.circle") }
                Text(busy ? "\(savedCount) из \(tracks.count)" : complete ? "Скачано" : "Скачать всё")
            }.font(PulseTheme.body(14, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 12)
                .background(PulseTheme.raised, in: Capsule())
        }.buttonStyle(PulseTactileButton()).disabled(tracks.isEmpty || busy || complete)
            .accessibilityLabel(busy ? "Скачивание: \(savedCount) из \(tracks.count)" : complete ? "Все треки скачаны" : "Скачать все треки плейлиста")
    }
}
struct PulseDownloadAction: View {
    let track: PulseTrack
    @ObservedObject var downloads: PulseDownloads
    var body: some View {
        Group {
        if downloads.tracks.contains(where: { $0.id == track.id }) {
            Button("Удалить скачанный файл", systemImage: "trash") { downloads.remove(track) }
        } else {
            Button(downloads.pending.contains(track.id) ? "Скачивается…" : "Скачать на устройство", systemImage: "arrow.down.circle") { Task { await downloads.download(track) } }.disabled(downloads.pending.contains(track.id))
        }
        }.alert("Скачивание", isPresented: Binding(get: { downloads.error != nil }, set: { if !$0 { downloads.error = nil } })) { Button("Понятно") { downloads.error = nil } } message: { Text(downloads.error ?? "") }
    }
}
enum PulseCoverCodec {
    static func encode(_ url: URL) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw URLError(.cannotDecodeContentData) }
        return try encodeSource(source)
    }
    static func encode(_ data: Data) throws -> Data {
        guard data.count <= 25 * 1024 * 1024 else { throw PulseAPIError(status: 413, message: "Выбери фото до 25 МБ") }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw URLError(.cannotDecodeContentData) }
        return try encodeSource(source)
    }
    private static func encodeSource(_ source: CGImageSource) throws -> Data {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw URLError(.cannotDecodeContentData) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination), data.length <= 300000 else { throw PulseAPIError(status: 413, message: "Выбери изображение меньшего размера") }
        return data as Data
    }
}

struct PulsePlaylistCover: View {
    let cover: String?
    var size: CGFloat = 30
    var symbol: String = "music.note.list"
    var fallback: PulseTrack? = nil
    var body: some View {
        Group {
            if let image = PulsePlaylistCoverImages.image(cover, size: size) {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else if let fallback { PulseArtworkView(track: fallback, size: size, radius: min(18, size * 0.12)) }
            else { Image(systemName: symbol).resizable().scaledToFit().padding(size * 0.25).foregroundStyle(PulseTheme.accent).background(PulseTheme.raised) }
        }.frame(width: size, height: size).clipped().clipShape(RoundedRectangle(cornerRadius: min(18, size * 0.12)))
    }
}

private enum PulsePlaylistCoverImages {
    static let cache: NSCache<NSString, CGImage> = {
        let value = NSCache<NSString, CGImage>(); value.countLimit = 32; value.totalCostLimit = 24 * 1024 * 1024; return value
    }()
    static func image(_ cover: String?, size: CGFloat) -> CGImage? {
        guard let cover, cover.hasPrefix("data:image/jpeg;base64,"), let data = Data(base64Encoded: String(cover.dropFirst("data:image/jpeg;base64,".count))) else { return nil }
        let pixels = Int(min(1024, max(60, size * 2)))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let key = "\(digest)|\(pixels)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height); return image
    }
}

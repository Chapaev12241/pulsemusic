import SwiftUI
import ImageIO
import CryptoKit
import UniformTypeIdentifiers

@MainActor
final class PulseDownloads: ObservableObject {
    @Published private(set) var tracks: [PulseTrack] = []
    @Published private(set) var pending = Set<String>()
    @Published var error: String?
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pulse/Downloads", isDirectory: true)
    }
    nonisolated static func localURL(_ id: String) -> URL? {
        guard id.count == 64, id.allSatisfy({ $0.isHexDigit }) else { return nil }
        for ext in ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"] {
            let url = directory.appendingPathComponent(id + "." + ext)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
    init() {
        if let data = try? Data(contentsOf: Self.directory.appendingPathComponent("index.json")), let saved = try? JSONDecoder().decode([PulseTrack].self, from: data) { tracks = saved.filter { Self.localURL($0.id) != nil } }
    }
    func download(_ track: PulseTrack) async {
        guard !pending.contains(track.id), Self.localURL(track.id) == nil, let url = URL(string: track.audio), url.scheme == "https", url.host == PulseAPI.base.host else { return }
        pending.insert(track.id); defer { pending.remove(track.id) }
        do {
            let (temporary, response) = try await URLSession.shared.download(from: url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.mimeType?.hasPrefix("audio/") == true else { throw URLError(.badServerResponse) }
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            var folder = Self.directory; var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try? folder.setResourceValues(flags)
            let formats = ["audio/mpeg": "mp3", "audio/mp3": "mp3", "audio/mp4": "m4a", "audio/x-m4a": "m4a", "audio/aac": "aac", "audio/wav": "wav", "audio/x-wav": "wav", "audio/flac": "flac", "audio/ogg": "ogg"]
            guard let ext = formats[http.mimeType ?? ""] else { throw URLError(.cannotDecodeContentData) }
            try FileManager.default.moveItem(at: temporary, to: Self.directory.appendingPathComponent(track.id + "." + ext))
            tracks.append(track); try persist()
        } catch { self.error = "Не удалось скачать: " + error.localizedDescription }
    }
    func remove(_ track: PulseTrack) {
        do { if let url = Self.localURL(track.id) { try FileManager.default.removeItem(at: url) }; tracks.removeAll { $0.id == track.id }; try persist() }
        catch { self.error = error.localizedDescription }
    }
    private func persist() throws { try JSONEncoder().encode(tracks).write(to: Self.directory.appendingPathComponent("index.json"), options: .atomic) }
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
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
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
    var body: some View {
        Group {
            if let image = PulsePlaylistCoverImages.image(cover, size: size) {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else { Image(systemName: symbol).resizable().scaledToFit().padding(size * 0.25).foregroundStyle(PulseTheme.accent).background(PulseTheme.raised) }
        }.frame(width: size, height: size).clipped().clipShape(RoundedRectangle(cornerRadius: min(24, size * 0.16)))
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

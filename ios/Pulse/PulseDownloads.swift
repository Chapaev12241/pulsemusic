import SwiftUI
import ImageIO
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
        let url = directory.appendingPathComponent(id + ".audio")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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
            try FileManager.default.moveItem(at: temporary, to: Self.directory.appendingPathComponent(track.id + ".audio"))
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
        if downloads.tracks.contains(where: { $0.id == track.id }) {
            Button("Удалить скачанный файл", systemImage: "trash") { downloads.remove(track) }
        } else {
            Button(downloads.pending.contains(track.id) ? "Скачивается…" : "Скачать на устройство", systemImage: "arrow.down.circle") { Task { await downloads.download(track) } }.disabled(downloads.pending.contains(track.id))
        }
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
    var body: some View {
        Group {
            if let cover, let data = Data(base64Encoded: String(cover.dropFirst("data:image/jpeg;base64,".count))), let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else { Image(systemName: "music.note.list").resizable().scaledToFit().padding(6) }
        }.frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

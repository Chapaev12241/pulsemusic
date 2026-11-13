import SwiftUI
import ImageIO

// Shared across cards, rows and the player. Decode off the main actor, coalesce
// duplicate requests and bound decoded-image memory independently of URLCache.
actor PulseArtworkCache {
    static let shared = PulseArtworkCache()
    private let images = NSCache<NSString, CGImage>()
    private var inflight: [String: Task<CGImage?, Never>] = [:]
    private var missing: [String: Date] = [:]
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let session: URLSession
    private let bundled: [String: Entry]
    private struct Entry: Decodable { let url: String }
    private struct Lookup: Decodable { let found: Bool?; let url: String? }
    init() {
        images.totalCostLimit = 64 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024, diskPath: "pulse-artwork")
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
        if let url = Bundle.main.url(forResource: "artwork-index", withExtension: "json"),
           let data = try? Data(contentsOf: url), let parsed = try? JSONDecoder().decode([String: Entry].self, from: data) { bundled = parsed }
        else { bundled = [:] }
    }
    static func key(artist: String, title: String) -> String {
        func norm(_ text: String) -> String {
            text.precomposedStringWithCompatibilityMapping.lowercased().replacingOccurrences(of: "ё", with: "е").unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
        }
        return norm(artist) + "|" + norm(title)
    }
    func image(for track: PulseTrack) async -> CGImage? {
        let key = Self.key(artist: track.artist, title: track.title) + "|hq2|" + (track.artwork ?? "")
        if let image = images.object(forKey: key as NSString) { return image }
        if let expiry = missing[key], expiry > Date() { return nil }
        if let task = inflight[key] { return await task.value }
        let preferred = track.artworkURL == nil ? bundled[Self.key(artist: track.artist, title: track.title)]?.url : nil
        let task = Task<CGImage?, Never> {
            await self.acquire()
            let result = await self.fetchImage(for: track, preferred: preferred)
            self.release()
            return result
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        if let image { images.setObject(image, forKey: key as NSString, cost: image.bytesPerRow * image.height) }
        else { missing[key] = Date().addingTimeInterval(3600) }
        return image
    }
    private func acquire() async {
        if running < 2 { running += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty { running -= 1 } else { waiters.removeFirst().resume() }
    }
    private func fetchImage(for track: PulseTrack, preferred: String?) async -> CGImage? {
            var candidates: [URL] = []
            if let preferred, let url = URL(string: preferred, relativeTo: PulseAPI.base) { candidates.append(url.absoluteURL) }
            if let url = track.artworkURL, !candidates.contains(url) { candidates.append(url) }
            for url in candidates {
                if let image = await Self.load(url, session: session) { return image }
            }
            var lookup = URLComponents(url: PulseAPI.base.appendingPathComponent("api/artwork"), resolvingAgainstBaseURL: false)!
            lookup.queryItems = [URLQueryItem(name: "artist", value: track.artist), URLQueryItem(name: "title", value: track.title)]
            if let url = lookup.url,
               let (data, response) = try? await session.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let result = try? JSONDecoder().decode(Lookup.self, from: data),
               let value = result.url, let artwork = URL(string: value), artwork.scheme == "https" {
                return await Self.load(artwork, session: session)
            }
            return nil
    }
    private static func load(_ url: URL, session: URLSession) async -> CGImage? {
        guard url.scheme == "https",
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
    }
}

struct PulseArtworkView: View {
    let track: PulseTrack?
    var size: CGFloat = 48
    var radius: CGFloat = 12
    @State private var image: CGImage?
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.19, green: 0.22, blue: 0.38), Color(red: 0.09, green: 0.08, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
            else {
                Circle().stroke(LinearGradient(colors: [PulseTheme.accent.opacity(0.75), .blue.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: max(6, size * 0.12)).padding(size * 0.21)
                Circle().fill(PulseTheme.accent).frame(width: max(4, size * 0.08), height: max(4, size * 0.08))
            }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: radius))
        .task(id: (track?.id ?? "") + "|" + (track?.artwork ?? "")) {
            image = nil
            if let track { let result = await PulseArtworkCache.shared.image(for: track); if !Task.isCancelled { image = result } }
        }
        .accessibilityHidden(true)
    }
}

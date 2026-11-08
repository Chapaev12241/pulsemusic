import SwiftUI

struct PulseLyricsResponse: Decodable {
    let found: Bool
    let instrumental: Bool
    let syncedLyrics: String
    let plainLyrics: String
    let source: String
    let sourceUrl: String
}
struct PulseLyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
}
enum PulseLRC {
    static func parse(_ text: String) -> [PulseLyricLine] {
        let timestamp = try! NSRegularExpression(pattern: #"\[(\d+):(\d{2}(?:\.\d+)?)\]"#)
        let tags = try! NSRegularExpression(pattern: #"\[[^\]]*\]|<\d+:\d{2}(?:\.\d+)?>"#)
        let offsetRE = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let full = text as NSString
        let offset = offsetRE.firstMatch(in: text, range: NSRange(location: 0, length: full.length)).flatMap { Double(full.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
        var values: [(Double, String)] = []
        for line in text.components(separatedBy: .newlines) {
            let raw = line as NSString, range = NSRange(location: 0, length: raw.length)
            let body = tags.stringByReplacingMatches(in: line, range: range, withTemplate: "").trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { continue }
            for match in timestamp.matches(in: line, range: range) {
                if let minutes = Double(raw.substring(with: match.range(at: 1))), let seconds = Double(raw.substring(with: match.range(at: 2))) {
                    values.append((max(0, minutes * 60 + seconds + offset), body))
                }
            }
        }
        return values.sorted { $0.0 < $1.0 }.enumerated().map { PulseLyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
    static func activeIndex(at time: Double, lines: [PulseLyricLine]) -> Int? {
        var low = 0, high = lines.count
        while low < high { let middle = (low + high) / 2; if lines[middle].time <= time { low = middle + 1 } else { high = middle } }
        return low > 0 ? low - 1 : nil
    }
}
@MainActor
final class PulseLyricsStore: ObservableObject {
    @Published private(set) var result: PulseLyricsResponse?
    @Published private(set) var lines: [PulseLyricLine] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var generation = UUID()
    private static var cache: [String: PulseLyricsResponse] = [:]
    private static var cacheOrder: [String] = []
    func load(_ track: PulseTrack?, duration: Double, force: Bool = false) async {
        let stamp = UUID(); generation = stamp; result = nil; lines = []; error = nil
        guard let track else { loading = false; return }
        loading = true
        defer { if generation == stamp { loading = false } }
        do {
            let value: PulseLyricsResponse
            if !force, let cached = Self.cache[track.id] { value = cached }
            else {
                var query = [URLQueryItem(name: "title", value: track.title), URLQueryItem(name: "artist", value: track.artist)]
                if duration.isFinite && duration > 0 { query.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
                value = try await PulseAPI.request("api/lyrics", query: query)
                if value.found || value.instrumental {
                    Self.cache[track.id] = value
                    Self.cacheOrder.removeAll { $0 == track.id }; Self.cacheOrder.append(track.id)
                    if Self.cacheOrder.count > 32 { Self.cache.removeValue(forKey: Self.cacheOrder.removeFirst()) }
                }
            }
            guard generation == stamp, !Task.isCancelled else { return }
            result = value; lines = PulseLRC.parse(value.syncedLyrics)
        } catch { if generation == stamp && !Task.isCancelled { self.error = "Не удалось загрузить текст. Попробуй ещё раз." } }
    }
}
struct PulseLyricsView: View {
    @ObservedObject var store: PulseStore
    @StateObject private var lyrics = PulseLyricsStore()
    @Environment(\.pulseReducedMotion) private var reducedMotion
    @State private var active: Int?
    @State private var follow = true
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Текст песни", systemImage: "text.quote").font(.headline)
                Spacer()
                Button { Task { await lyrics.load(store.currentTrack, duration: store.playback.duration, force: true) } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(PulseIconButton())
            }
            if lyrics.loading { ProgressView("Ищем текст…").font(.callout).frame(maxWidth: .infinity, minHeight: 120) }
            else if let error = lyrics.error { Text(error).foregroundStyle(PulseTheme.muted) }
            else if !lyrics.lines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(lyrics.lines) { line in
                                Button { store.seek(line.time); follow = true } label: {
                                    Text(line.text).font(.system(size: 24, weight: active == line.id ? .semibold : .medium))
                                        .foregroundStyle(active == line.id ? Color.white : PulseTheme.muted.opacity(active.map { line.id < $0 } == true ? 0.5 : 0.8))
                                        .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading).padding(.vertical, 2)
                                }.buttonStyle(.plain).id(line.id)
                            }
                        }.padding(.vertical, 20)
                    }
                    .frame(height: 330)
                    .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in follow = false })
                    .onChange(of: active) { _, value in
                        guard follow, let value else { return }
                        withAnimation(reducedMotion ? nil : .easeOut(duration: 0.3)) { proxy.scrollTo(value, anchor: .center) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !follow { Button("К текущей строке") { follow = true; if let active { withAnimation(reducedMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo(active, anchor: .center) } } }.font(.caption).buttonStyle(.bordered).tint(PulseTheme.accent) }
                    }
                }
            } else {
                Text(lyrics.result?.instrumental == true ? "Инструментальная композиция" : lyrics.result?.plainLyrics.isEmpty == false ? lyrics.result!.plainLyrics : "Текст пока не найден").font(.system(size: 17)).lineSpacing(8).foregroundStyle(PulseTheme.muted).textSelection(.enabled)
            }
            if let value = lyrics.result, let url = URL(string: value.sourceUrl), url.scheme == "https", !value.source.isEmpty {
                Link("\(value.source) ↗", destination: url).font(.caption).foregroundStyle(PulseTheme.accent)
            }
        }
        .padding(22).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 22))
        .task(id: store.currentID) { active = nil; follow = true; await lyrics.load(store.currentTrack, duration: store.playback.duration) }
        .onReceive(store.playback.$time) { time in
            let next = PulseLRC.activeIndex(at: time, lines: lyrics.lines)
            if next != active { active = next }
        }
    }
}

enum PulseTrackSwipe {
    static func direction(horizontal: CGFloat, vertical: CGFloat) -> Int? {
        guard abs(horizontal) >= 64, abs(horizontal) > abs(vertical) * 1.6 else { return nil }
        return horizontal < 0 ? 1 : -1
    }
}

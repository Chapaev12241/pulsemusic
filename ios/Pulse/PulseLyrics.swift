import SwiftUI

struct PulseLyricsResponse: Decodable {
    let found: Bool
    let instrumental: Bool
    let syncedLyrics: String
    let plainLyrics: String
    let source: String
    let sourceUrl: String
}
struct PulseLyricWord: Equatable {
    let text: String
    let start: Double
    let end: Double
}
struct PulseLyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
    var marks: [PulseLyricWord] = []
}
enum PulseLRC {
    static func parse(_ text: String) -> [PulseLyricLine] {
        let timestamp = try! NSRegularExpression(pattern: #"\[(\d+):(\d{2}(?:\.\d+)?)\]"#)
        let tags = try! NSRegularExpression(pattern: #"\[[^\]]*\]"#)
        let wordRE = try! NSRegularExpression(pattern: #"<(\d+):(\d{2}(?:\.\d+)?)>([^<]*)"#)
        let wordTags = try! NSRegularExpression(pattern: #"<\d+:\d{2}(?:\.\d+)?>"#)
        let offsetRE = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let full = text as NSString
        let offset = offsetRE.firstMatch(in: text, range: NSRange(location: 0, length: full.length)).flatMap { Double(full.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
        func stamp(_ raw: NSString, _ match: NSTextCheckingResult) -> Double {
            (Double(raw.substring(with: match.range(at: 1))) ?? 0) * 60 + (Double(raw.substring(with: match.range(at: 2))) ?? 0)
        }
        var values: [PulseLyricLine] = []
        for line in text.components(separatedBy: .newlines) {
            let raw = line as NSString, range = NSRange(location: 0, length: raw.length)
            let times = timestamp.matches(in: line, range: range)
            guard let first = times.first else { continue }
            let clean = tags.stringByReplacingMatches(in: line, range: range, withTemplate: "")
            let cleanRange = NSRange(location: 0, length: (clean as NSString).length)
            let body = wordTags.stringByReplacingMatches(in: clean, range: cleanRange, withTemplate: "").trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { continue }
            let rawMarks = wordRE.matches(in: clean, range: cleanRange)
            let nsClean = clean as NSString
            for time in times {
                let delta = stamp(raw, time) - stamp(raw, first)
                var marks = rawMarks.enumerated().compactMap { index, match -> PulseLyricWord? in
                    let word = nsClean.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                    guard !word.isEmpty else { return nil }
                    let end = index + 1 < rawMarks.count ? max(0, stamp(nsClean, rawMarks[index + 1]) + delta + offset) : 0
                    return PulseLyricWord(text: word, start: max(0, stamp(nsClean, match) + delta + offset), end: end)
                }
                if let firstMark = rawMarks.first {
                    let prefix = nsClean.substring(to: firstMark.range.location).trimmingCharacters(in: .whitespaces)
                    if !prefix.isEmpty { marks.insert(PulseLyricWord(text: prefix, start: max(0, stamp(raw, time) + offset), end: max(0, stamp(nsClean, firstMark) + delta + offset)), at: 0) }
                }
                values.append(PulseLyricLine(id: 0, time: max(0, stamp(raw, time) + offset), text: body, marks: marks))
            }
        }
        return values.sorted { $0.time < $1.time }.enumerated().map { PulseLyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text, marks: $0.element.marks) }
    }
    // Enhanced LRC uses supplied word marks. Ordinary LRC gets an explicitly
    // estimated syllable-weighted timeline, matching the website's behavior.
    static func words(for line: PulseLyricLine, next: Double?, duration: Double) -> [PulseLyricWord] {
        let tokens = line.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return [] }
        let boundary = next.flatMap { $0 > line.time ? $0 : nil } ?? (duration.isFinite && duration > line.time ? duration : line.time + max(2, Double(tokens.count) * 0.6))
        let segments: [(String, Double, Double)]
        if !line.marks.isEmpty {
            segments = line.marks.enumerated().map { i, mark in
                let end = mark.end > mark.start ? mark.end : i + 1 < line.marks.count ? line.marks[i + 1].start : min(boundary, mark.start + 1)
                return (mark.text, mark.start, max(mark.start + 0.04, end))
            }
        } else {
            segments = [(line.text, line.time, min(boundary, line.time + max(1.2, Double(tokens.count) * 0.7 + 0.6)))]
        }
        return segments.flatMap { text, start, end -> [PulseLyricWord] in
            let parts = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let vowels = Set("aeiouyаеёиоуыэюя")
            let weights = parts.map { word in Double(max(1, word.lowercased().filter { vowels.contains($0) }.count)) + Double(min(14, word.count)) * 0.08 }
            let total = max(1, weights.reduce(0, +)); var cursor = start
            return parts.enumerated().map { i, word in
                let begin = cursor; cursor += max(0.04, end - start) * weights[i] / total
                return PulseLyricWord(text: word, start: begin, end: cursor)
            }
        }
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
                                    Group {
                                        if active == line.id {
                                            PulseLyricWordsView(playback: store.playback, words: PulseLRC.words(for: line, next: lyrics.lines.dropFirst(line.id + 1).first?.time, duration: store.playback.duration))
                                        } else {
                                            Text(line.text).font(.system(size: 24, weight: .semibold)).foregroundStyle(PulseTheme.muted.opacity(active.map { line.id < $0 } == true ? 0.5 : 0.8))
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading).padding(.vertical, 2)
                                }.buttonStyle(PulseTactileButton()).id(line.id)
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
            if !lyrics.lines.isEmpty && lyrics.lines.contains(where: { $0.marks.isEmpty }) {
                Text("Подсветка слов рассчитана по строкам").font(.caption2).foregroundStyle(PulseTheme.muted)
            }
            if let value = lyrics.result, let url = URL(string: value.sourceUrl), url.scheme == "https", !value.source.isEmpty {
                Link("\(value.source) ↗", destination: url).font(.caption).foregroundStyle(PulseTheme.accent)
            }
        }
        .padding(22).pulseGlass(cornerRadius: 22)
        .task(id: store.currentID) { active = nil; follow = true; await lyrics.load(store.currentTrack, duration: store.playback.duration) }
        .onReceive(store.playback.$time) { time in
            let next = PulseLRC.activeIndex(at: time, lines: lyrics.lines)
            if next != active { active = next }
        }
    }
}

enum PulseTrackSwipe {
    static func direction(horizontal: CGFloat, vertical: CGFloat, start: CGPoint? = nil, excluding: CGRect = .null) -> Int? {
        if let start, excluding.insetBy(dx: -8, dy: -8).contains(start) { return nil }
        guard abs(horizontal) >= 64, abs(horizontal) > abs(vertical) * 1.6 else { return nil }
        return horizontal < 0 ? 1 : -1
    }
}

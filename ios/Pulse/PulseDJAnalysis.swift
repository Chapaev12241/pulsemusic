import Foundation
import AVFoundation

struct PulseDJFeatures: Codable, Equatable {
    let id: String
    let bpm: Double?
    let confidence: Double
    let energy: Double
    let brightness: Double
    let bass: Double
}
enum PulseDJTransition: String, Codable, CaseIterable, Identifiable {
    case blend, bassSwap, echo, filter
    var id: String { rawValue }
    var title: String {
        switch self { case .blend: return "Плавное сведение"; case .bassSwap: return "Передача баса"; case .echo: return "Эхо"; case .filter: return "Фильтр" }
    }
}
struct PulseDJMix: Codable {
    let effect: PulseDJTransition
    let duration: Double
}
enum PulseDJMatcher {
    static func tempoDistance(_ a: Double?, _ b: Double?) -> Double {
        guard let a, let b, a > 0, b > 0 else { return 0.3 }
        return [b / a, b * 2 / a, b / 2 / a].map { abs(log2($0)) }.min() ?? 1
    }
    static func distance(_ a: PulseDJFeatures, _ b: PulseDJFeatures) -> Double {
        tempoDistance(a.bpm, b.bpm) * 3 + abs(a.energy - b.energy) * 1.4 + abs(a.brightness - b.brightness) * 0.8 + abs(a.bass - b.bass) * 0.8
    }
    // A nearest-neighbor model over measured audio features; no title/BPM guesses.
    static func order(_ values: [PulseDJFeatures], seed: String?) -> [PulseDJFeatures] {
        var remaining = values; var result: [PulseDJFeatures] = []
        guard !remaining.isEmpty else { return [] }
        let first = remaining.firstIndex { $0.id == seed } ?? remaining.indices.min { abs(remaining[$0].energy - 0.55) < abs(remaining[$1].energy - 0.55) }!
        result.append(remaining.remove(at: first))
        while let last = result.last, !remaining.isEmpty {
            // A gentle energy arc avoids a mix that only gets louder.
            let target = 0.48 + 0.18 * sin(Double(result.count) * .pi / max(4, Double(values.count)))
            let best = remaining.indices.min { distance(last, remaining[$0]) + abs(remaining[$0].energy - target) * 0.25 < distance(last, remaining[$1]) + abs(remaining[$1].energy - target) * 0.25 }!
            result.append(remaining.remove(at: best))
        }
        return result
    }
    static func transition(from a: PulseDJFeatures, to b: PulseDJFeatures, index: Int) -> PulseDJMix {
        let close = tempoDistance(a.bpm, b.bpm) < 0.12 && min(a.confidence, b.confidence) > 0.15
        let effect: PulseDJTransition = close && min(a.bass, b.bass) > 0.2 ? .bassSwap : abs(a.energy - b.energy) > 0.2 ? .echo : index % 3 == 2 ? .filter : .blend
        let beats = effect == .bassSwap ? 16.0 : 8.0
        let length = a.bpm.map { beats * 60 / $0 } ?? 5
        return PulseDJMix(effect: effect, duration: min(9, max(3, length)))
    }
}

// Bounded, streaming PCM analysis. Only the first minute after the intro is
// decoded. Cached features survive restarts; downloaded audio is removed.
actor PulseDJAnalyzer {
    static let shared = PulseDJAnalyzer()
    private var cache: [String: PulseDJFeatures] = [:]
    private let cacheURL: URL
    init() {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Pulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        cacheURL = folder.appendingPathComponent("dj-features-v1.json")
        if let data = try? Data(contentsOf: cacheURL), let saved = try? JSONDecoder().decode([String: PulseDJFeatures].self, from: data) { cache = saved }
    }
    func analyze(_ track: PulseTrack) async throws -> PulseDJFeatures {
        if let value = cache[track.id] { return value }
        guard let url = URL(string: track.audio), url.scheme == "https", url.host == PulseAPI.base.host else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.timeoutInterval = 45
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        let size = (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size <= 30 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
        try Task.checkCancellation()
        let value = try Self.decode(id: track.id, url: temporary)
        cache[track.id] = value
        if cache.count > 600 { cache = Dictionary(uniqueKeysWithValues: cache.values.sorted { $0.id < $1.id }.prefix(600).map { ($0.id, $0) }) }
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheURL, options: .atomic) }
        return value
    }
    private static func decode(id: String, url: URL) throws -> PulseDJFeatures {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat, rate = format.sampleRate
        guard rate > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { throw URLError(.cannotDecodeContentData) }
        file.framePosition = min(file.length / 5, AVAudioFramePosition(rate * 20))
        let stop = min(file.length, file.framePosition + AVAudioFramePosition(rate * 60))
        let decimation = max(1, Int(rate / 11025)), analysisRate = rate / Double(decimation)
        let hop = max(1, Int(analysisRate * 0.0232))
        let alpha = min(1, 2 * Double.pi * 180 / analysisRate)
        var envelope: [Double] = [], low = 0.0, sum = 0.0, lowSum = 0.0, block = 0.0
        var total = 0, inBlock = 0, crossings = 0, previous = 0.0, sourceFrame = 0
        while file.framePosition < stop {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(4096, stop - file.framePosition)))
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            for i in 0..<Int(buffer.frameLength) {
                sourceFrame += 1
                guard sourceFrame % decimation == 0 else { continue }
                let raw = Double(channels[0][i]); let x = raw.isFinite ? raw : 0
                low += alpha * (x - low)
                sum += x * x; lowSum += low * low; block += low * low
                if (x >= 0) != (previous >= 0) { crossings += 1 }; previous = x
                total += 1; inBlock += 1
                if inBlock == hop { envelope.append(sqrt(block / Double(hop))); block = 0; inBlock = 0 }
            }
        }
        guard total > Int(analysisRate * 4) else { throw URLError(.cannotDecodeContentData) }
        return features(id: id, envelope: envelope, envelopeRate: analysisRate / Double(hop), rms: sqrt(sum / Double(total)), bassRatio: sqrt(lowSum / max(0.000001, sum)), crossingRate: Double(crossings) / Double(total))
    }
    static func features(id: String, envelope: [Double], envelopeRate: Double, rms: Double, bassRatio: Double, crossingRate: Double) -> PulseDJFeatures {
        let onset = envelope.enumerated().map { i, value in max(0, value - (i > 0 ? envelope[i - 1] : value)) }
        let mean = onset.isEmpty ? 0 : onset.reduce(0, +) / Double(onset.count)
        let centered = onset.map { $0 - mean }
        let lo = max(1, Int(envelopeRate * 60 / 180)), hi = min(centered.count / 2, Int(envelopeRate * 60 / 70))
        var best = 0.0, bestLag = 0
        if hi >= lo {
            for lag in lo...hi {
                var dot = 0.0, aa = 0.0, bb = 0.0
                for i in lag..<centered.count { let a = centered[i], b = centered[i - lag]; dot += a * b; aa += a * a; bb += b * b }
                let score = dot / max(0.00000001, sqrt(aa * bb))
                if score > best { best = score; bestLag = lag }
            }
        }
        let bpm = bestLag > 0 && best > 0.1 ? envelopeRate * 60 / Double(bestLag) : nil
        return PulseDJFeatures(id: id, bpm: bpm, confidence: best, energy: min(1, max(0, (20 * log10(max(0.00001, rms)) + 42) / 36)), brightness: min(1, max(0, crossingRate * 5)), bass: min(1, max(0, bassRatio)))
    }
}

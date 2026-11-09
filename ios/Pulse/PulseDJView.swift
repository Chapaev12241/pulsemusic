import SwiftUI

@MainActor
final class PulseDJStore: ObservableObject {
    @Published private(set) var queue: [PulseDJFeatures] = []
    @Published private(set) var building = false
    @Published private(set) var progress = 0
    @Published private(set) var total = 0
    @Published private(set) var error: String?
    @Published private(set) var skipped = 0
    private var task: Task<Void, Never>?
    private var generation = UUID()
    func clear() { generation = UUID(); task?.cancel(); task = nil; queue = []; building = false; error = nil; progress = 0 }
    func cancel() { generation = UUID(); task?.cancel(); task = nil; building = false }
    func build(tracks: [PulseTrack], seed: PulseTrack?, liked: Set<String>) {
        cancel(); let stamp = generation
        let preferred = Set(tracks.filter { liked.contains($0.id) }.map(\.artist))
        var candidates = tracks.shuffled().sorted { a, b in
            let left = a.id == seed?.id ? 2 : preferred.contains(a.artist) ? 1 : 0
            let right = b.id == seed?.id ? 2 : preferred.contains(b.artist) ? 1 : 0
            return left > right
        }
        // Keep variety instead of analyzing sixteen tracks by the same artist.
        var counts: [String: Int] = [:]
        candidates = candidates.filter { track in counts[track.artist, default: 0] += 1; return counts[track.artist, default: 0] <= 4 }
        candidates = Array(candidates.prefix(16))
        total = candidates.count; progress = 0; skipped = 0; error = nil; building = true
        task = Task { [weak self, candidates] in
            var values: [PulseDJFeatures] = []
            for track in candidates {
                guard !Task.isCancelled else { return }
                do {
                    let value = try await PulseDJAnalyzer.shared.analyze(track)
                    guard let self, self.generation == stamp, !Task.isCancelled else { return }
                    values.append(value)
                } catch {
                    guard let self, self.generation == stamp, !Task.isCancelled else { return }
                    self.skipped += 1
                }
                guard let self, self.generation == stamp else { return }
                self.progress += 1
            }
            guard let self, self.generation == stamp, !Task.isCancelled else { return }
            self.queue = PulseDJMatcher.order(values, seed: seed?.id); self.building = false
            if values.count < 2 { self.error = "Для микса нужны хотя бы два доступных трека. Обнови медиатеку и попробуй ещё раз." }
        }
    }
    var transitions: [String: PulseDJMix] {
        guard queue.count > 1 else { return [:] }
        return Dictionary(uniqueKeysWithValues: queue.enumerated().map { index, item in
            (queue[(index + 1) % queue.count].id, PulseDJMatcher.transition(from: item, to: queue[(index + 1) % queue.count], index: index))
        })
    }
}

struct PulseDJView: View {
    @ObservedObject var store: PulseStore
    @ObservedObject private var dj: PulseDJStore
    @State private var effect = "auto"
    init(store: PulseStore) { self.store = store; dj = store.djLibrary }
    private var tracks: [PulseTrack] { PulseLibrary.ordered(dj.queue.map(\.id), in: store.tracks) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DJ").font(PulseTheme.heading(68))
                        Text("Одна волна.\nНепрерывный микс.").font(.title2.bold())
                        Text("Подбор по темпу, энергии, басу и яркости звука.").font(.callout).foregroundStyle(PulseTheme.muted)
                    }
                    Spacer()
                    PulseReactiveVinyl(playback: store.playback, beat: store.beat).frame(width: 100, height: 100).padding(8)
                }.padding(24).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 26))
                if dj.building {
                    ProgressView(value: Double(dj.progress), total: Double(max(1, dj.total)))
                    HStack {
                        Text("Слушаю и анализирую · \(dj.progress) / \(dj.total)").font(.callout).foregroundStyle(PulseTheme.muted)
                        Spacer(); Button("Отменить") { dj.cancel() }.buttonStyle(.bordered)
                    }
                } else {
                    HStack(spacing: 12) {
                        Button { dj.build(tracks: store.tracks, seed: store.currentTrack, liked: Set(store.state.liked)) } label: {
                            Label(tracks.isEmpty ? "Собрать мой микс" : "Новый микс", systemImage: "sparkles")
                        }.buttonStyle(PulsePrimaryButton()).disabled(store.tracks.count < 2)
                        if tracks.count > 1 {
                            Button { play(tracks[0]) } label: { Label("Слушать", systemImage: "play.fill") }.buttonStyle(.bordered).tint(PulseTheme.accent)
                        }
                    }
                }
                Picker("Переходы", selection: $effect) {
                    Text("Авто · по звучанию").tag("auto")
                    ForEach(PulseDJTransition.allCases) { item in Text(item.title).tag(item.rawValue) }
                }.pickerStyle(.menu)
                Text("Музыка подбирается по звучанию на устройстве. Первый анализ загружает до 16 треков и сохраняет результаты для следующих миксов. BPM приблизительный; песни играют в исходной скорости.")
                    .font(.caption).foregroundStyle(PulseTheme.muted)
                if let error = dj.error { Text(error).foregroundStyle(.orange) }
                if dj.skipped > 0 { Text("Пропущено недоступных для анализа треков: \(dj.skipped)").font(.caption).foregroundStyle(PulseTheme.muted) }
                if !tracks.isEmpty {
                    Text("Твой DJ-плейлист · \(tracks.count)").font(.title3.bold())
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            VStack(alignment: .leading, spacing: 4) {
                                PulseTrackRow(track: track, index: index + 1) { play(track) }
                                if let value = dj.queue.first(where: { $0.id == track.id }) {
                                    HStack(spacing: 12) {
                                        Text(value.bpm.map { "≈ \(Int($0.rounded())) BPM" } ?? "Свободный ритм")
                                        Text("Энергия \(Int(value.energy * 100))%")
                                        if let transition = dj.transitions[track.id], index > 0 { Text(transition.effect.title) }
                                    }.font(.caption2).foregroundStyle(PulseTheme.accent).padding(.leading, 70).padding(.bottom, 12)
                                }
                                Rectangle().fill(PulseTheme.line).frame(height: 1)
                            }
                        }
                    }
                } else if !dj.building {
                    Text("Начни с любимой песни: запусти её и собери микс вокруг этого звучания.").font(.callout).foregroundStyle(PulseTheme.muted).padding(.vertical, 20)
                }
            }.padding(22)
        }
    }
    private func play(_ track: PulseTrack) {
        var transitions = dj.transitions
        if let fixed = PulseDJTransition(rawValue: effect) { transitions = transitions.mapValues { PulseDJMix(effect: fixed, duration: $0.duration) } }
        store.playDJ(track, within: tracks, transitions: transitions)
    }
}

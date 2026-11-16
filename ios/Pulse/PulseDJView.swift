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
    private var owner = ""
    func configure(owner: String) {
        guard self.owner != owner else { return }
        clear(); self.owner = owner
        if !owner.isEmpty, let data = UserDefaults.standard.data(forKey: "pulse_dj_queue_" + owner),
           let values = try? JSONDecoder().decode([PulseDJFeatures].self, from: data) {
            var seen = Set<String>(); queue = Array(values.filter { seen.insert($0.id).inserted }.prefix(16))
        }
    }
    func clear() { generation = UUID(); owner = ""; task?.cancel(); task = nil; queue = []; building = false; error = nil; progress = 0 }
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
            if !self.owner.isEmpty, let data = try? JSONEncoder().encode(self.queue) { UserDefaults.standard.set(data, forKey: "pulse_dj_queue_" + self.owner) }
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
    @Environment(\.pulseReducedMotion) private var reducedMotion
    @State private var showDetails = false
    @AppStorage("pulse_dj_transition") private var effect = "auto"
    init(store: PulseStore) { self.store = store; dj = store.djLibrary }
    private var tracks: [PulseTrack] { PulseLibrary.ordered(dj.queue.map(\.id), in: store.tracks) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Твой DJ").font(PulseTheme.display(36))
                        Text("Без пауз.\nВ твоём ритме.").font(PulseTheme.body(20, weight: .medium)).foregroundStyle(PulseTheme.muted)
                    }
                    Spacer()
                    PulseReactiveVinyl(playback: store.playback, beat: store.beat).frame(width: 96, height: 96).padding(4)
                }.padding(26).pulseGlass(cornerRadius: 28, style: .hero)
                if dj.building {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Находим твой ритм").font(PulseTheme.body(15, weight: .medium))
                            Spacer()
                            Text("\(dj.progress) / \(dj.total)").font(PulseTheme.body(12)).monospacedDigit().foregroundStyle(PulseTheme.muted)
                        }
                        ProgressView(value: Double(dj.progress), total: Double(max(1, dj.total)))
                        Button("Отменить анализ") { dj.cancel() }.font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted).buttonStyle(PulseTactileButton())
                    }.padding(20).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 20))
                } else {
                    HStack(spacing: 12) {
                        Button { dj.build(tracks: store.tracks, seed: store.currentTrack, liked: Set(store.state.liked)) } label: {
                            Label(tracks.isEmpty ? "Создать микс" : "Новый микс", systemImage: "waveform")
                        }.buttonStyle(PulsePrimaryButton()).disabled(store.tracks.count < 2)
                        if tracks.count > 1 {
                            Button { play(tracks[0]) } label: { Label("Слушать", systemImage: "play.fill") }.buttonStyle(.bordered).tint(PulseTheme.accent)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Переходы", selection: $effect) {
                        Text("Авто · по звучанию").tag("auto")
                        ForEach(PulseDJTransition.allCases) { item in Text(item.title).tag(item.rawValue) }
                    }.pickerStyle(.menu).font(PulseTheme.body(14))
                    DisclosureGroup("Как работает микс", isExpanded: $showDetails) {
                        Text("Pulse сопоставляет темп, энергию и характер звучания на устройстве. Первый анализ загружает до 16 треков, затем использует сохранённые результаты. Темп приблизительный; песни играют в исходной скорости.")
                            .font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted).padding(.top, 8)
                    }.font(PulseTheme.body(13)).foregroundStyle(PulseTheme.muted)
                }.padding(20).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 20))
                if let error = dj.error { Text(error).foregroundStyle(.orange) }
                if dj.skipped > 0 { Text("Пропущено недоступных для анализа треков: \(dj.skipped)").font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted) }
                if !tracks.isEmpty {
                    HStack { Text("В миксе").font(PulseTheme.body(22, weight: .semibold)); Spacer(); Text("\(tracks.count) треков").font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted) }
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            VStack(alignment: .leading, spacing: 4) {
                                PulseTrackRow(track: track, index: index + 1) { play(track) }
                                if let value = dj.queue.first(where: { $0.id == track.id }) {
                                    HStack(spacing: 12) {
                                        Text(value.bpm.map { "≈ \(Int($0.rounded())) BPM" } ?? "Свободный ритм")
                                        Text("Энергия \(Int(value.energy * 100))%")
                                        if let transition = dj.transitions[track.id], index > 0 { Text(transition.effect.title) }
                                    }.font(PulseTheme.body(11)).foregroundStyle(PulseTheme.accent).padding(.leading, 70).padding(.bottom, 12)
                                }
                                Rectangle().fill(PulseTheme.line).frame(height: 1)
                            }
                        }
                    }
                } else if !dj.building {
                    Text("Начни с любимой песни: запусти её и собери микс вокруг этого звучания.").font(PulseTheme.body(14)).foregroundStyle(PulseTheme.muted).padding(.vertical, 20)
                }
            }.padding(24).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
        .animation(reducedMotion ? nil : .easeInOut(duration: 0.24), value: dj.building)
        .animation(reducedMotion ? nil : .easeInOut(duration: 0.24), value: showDetails)
    }
    private func play(_ track: PulseTrack) {
        var transitions = dj.transitions
        if let fixed = PulseDJTransition(rawValue: effect) { transitions = transitions.mapValues { PulseDJMix(effect: fixed, duration: $0.duration) } }
        store.playDJ(track, within: tracks, transitions: transitions)
    }
}

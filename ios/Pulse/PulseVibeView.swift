import SwiftUI

struct PulseVibeView: View {
    @ObservedObject var store: PulseStore
    @ObservedObject private var ai: PulseAIStore
    @ObservedObject private var model: PulseAIModelStore
    @Environment(\.scenePhase) private var phase
    @State private var mode = PulseVibeMode.personal
    @State private var seed = ""
    @State private var prompt = ""
    @State private var discovery = 0.55
    @State private var saving = false
    @State private var showAccount = false
    init(store: PulseStore) { self.store = store; ai = store.ai; model = store.ai.model }
    private var artists: [String] { Array(Set(store.tracks.map(\.artist))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    private var result: [PulseTrack] { PulseLibrary.ordered(ai.draft?.tracks ?? [], in: store.tracks) }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("PULSE AI · НА УСТРОЙСТВЕ", systemImage: "sparkles").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(PulseTheme.accent)
                    Text("Музыка, которая\nчувствует твой вайб.").font(PulseTheme.heading(36)).fixedSize(horizontal: false, vertical: true)
                    Text("Расскажи о настроении. ИИ выберет музыку из каталога с учётом твоих лайков и истории.").font(.callout).foregroundStyle(PulseTheme.muted)
                }
                modelPanel
                if model.ready {
                    VStack(alignment: .leading, spacing: 18) {
                        Picker("Что подобрать", selection: $mode) { ForEach(PulseVibeMode.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).disabled(ai.building)
                        if mode != .personal {
                            Picker("Исполнитель", selection: $seed) {
                                Text("Выбери исполнителя").tag("")
                                ForEach(artists, id: \.self) { Text($0).tag($0) }
                            }.disabled(ai.building)
                        }
                        TextField("Ночной город, русский рэп, без грусти…", text: $prompt, axis: .vertical).lineLimit(2...4).padding(14).background(PulseTheme.background, in: RoundedRectangle(cornerRadius: 14)).disabled(ai.building)
                        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) {
                            ForEach(["Ночная поездка", "Больше энергии", "Спокойный вечер", "Открой новое"], id: \.self) { value in
                                Button { prompt = value } label: { Text(value).font(.caption).padding(.horizontal, 12).padding(.vertical, 8).background(PulseTheme.raised, in: Capsule()) }.buttonStyle(PulseTactileButton()).disabled(ai.building)
                            }
                        } }
                        HStack { Text("Знакомое"); Slider(value: $discovery, in: 0...1).accessibilityLabel("Доля открытий"); Text("Открытия") }.font(.caption).foregroundStyle(PulseTheme.muted).disabled(ai.building)
                        if ai.building {
                            HStack(spacing: 12) { ProgressView().controlSize(.small); Text("ИИ собирает твой саундтрек…").font(.callout); Spacer(); Button("Отмена") { ai.cancel() } }
                            Text("Подбор выполняется отдельно от плеера. На первом запуске может понадобиться немного больше времени.").font(.caption).foregroundStyle(PulseTheme.muted)
                        } else {
                            Button { generate() } label: { Label(ai.draft == nil ? "Создать ИИ-плейлист" : "Собрать по-новому", systemImage: "sparkles").frame(maxWidth: .infinity) }.buttonStyle(PulsePrimaryButton()).disabled(store.tracks.isEmpty || (mode != .personal && seed.isEmpty))
                        }
                    }.padding(20).pulseGlass(cornerRadius: 22)
                }
                if let error = ai.error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(PulseTheme.muted) }
                if let draft = ai.draft {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(draft.name).font(.title2.bold())
                                Text(draft.summary).font(.callout).foregroundStyle(PulseTheme.muted)
                                Text("\(result.count) треков · \(draft.artists.count) исполнителей").font(.caption).foregroundStyle(PulseTheme.accent)
                            }; Spacer(); Image(systemName: "waveform.circle.fill").font(.system(size: 38)).foregroundStyle(PulseTheme.accent)
                        }
                        Text(draft.artists.joined(separator: " · ")).font(.caption).foregroundStyle(PulseTheme.muted)
                        HStack(spacing: 12) {
                            Button { if let first = result.first { store.play(first, within: result) } } label: { Label("Слушать", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(PulsePrimaryButton()).disabled(result.isEmpty)
                            Button {
                                if !store.signedIn { showAccount = true; return }
                                saving = true
                                Task { if await store.saveAIPlaylist(draft) { ai.markSaved() }; saving = false }
                            } label: { Label(ai.saved ? "Сохранено" : saving ? "Сохраняем…" : "Сохранить", systemImage: ai.saved ? "checkmark" : "plus").font(.callout).frame(maxWidth: .infinity).padding(.vertical, 13).background(PulseTheme.raised, in: Capsule()) }.buttonStyle(PulseTactileButton()).disabled(saving || ai.saved || result.isEmpty)
                        }
                    }.padding(20).pulseGlass(cornerRadius: 22)
                    ForEach(Array(result.enumerated()), id: \.element.id) { index, track in PulseTrackRow(track: track, index: index + 1) { store.play(track, within: result) } }
                }
                Text("ИИ выбирает только доступные треки. Если нужного исполнителя ещё нет в Pulse, сначала добавь его через импорт. Сохранённые плейлисты доступны на сайте и других устройствах.").font(.caption).foregroundStyle(PulseTheme.muted)
            }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 28)
        }
        .sheet(isPresented: $showAccount) { PulseAccountView().environmentObject(store).preferredColorScheme(.dark) }
        .onChange(of: phase) { _, value in if value != .active { ai.cancel() } }
        .onDisappear { ai.cancel() }
    }
    private var modelPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Image(systemName: model.ready ? "checkmark.seal.fill" : "arrow.down.circle").foregroundStyle(PulseTheme.accent); Text(model.ready ? "Локальный ИИ готов" : "Включи локальный ИИ").font(.headline); Spacer() }
            if !model.ready {
                Text("Один раз скачай модель Qwen3 · \(PulseAIModel.downloadSize). После этого ИИ работает без API-ключа. Твои запросы и история прослушиваний остаются на устройстве.").font(.callout).foregroundStyle(PulseTheme.muted)
                if model.downloading {
                    ProgressView(value: model.progress); HStack { Text(model.status).font(.caption); Spacer(); Text("\(Int(model.progress * 100))%").font(.caption.monospacedDigit()); Button("Отмена") { model.cancel() } }
                } else { Button { model.download() } label: { Label("Скачать ИИ · \(PulseAIModel.downloadSize)", systemImage: "arrow.down").frame(maxWidth: .infinity) }.buttonStyle(PulsePrimaryButton()) }
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(PulseTheme.muted) }
            DisclosureGroup("О модели и памяти") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(PulseAIModel.modelName) · Apache 2.0. Модель загружается в память только на время подбора. Для проигрывания облачных треков и синхронизации нужен интернет.").font(.caption).foregroundStyle(PulseTheme.muted)
                    Link("Модель и лицензия ↗", destination: URL(string: "https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF")!).font(.caption)
                    if model.ready { Button("Удалить модель · освободить \(PulseAIModel.downloadSize)", role: .destructive) { ai.cancel(); model.remove() }.font(.caption).disabled(ai.building) }
                }.padding(.top, 10)
            }.font(.caption)
        }.padding(20).pulseGlass(cornerRadius: 22)
    }
    private func generate() { ai.generate(tracks: store.tracks, state: store.state, prompt: prompt.isEmpty ? "Подбери музыку для моего вайба" : prompt, mode: mode, seed: seed, discovery: discovery, playing: !store.paused) }
}

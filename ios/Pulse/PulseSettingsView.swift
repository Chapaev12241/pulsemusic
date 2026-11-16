import SwiftUI

struct PulseSettingsView: View {
    @ObservedObject var store: PulseStore
    @ObservedObject private var equalizer: PulseEqualizerSettings
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @State private var advancedEQ = false
    @State private var cloudDetails = false
    @AppStorage("pulse_haptics") private var haptics = true
    @AppStorage("pulse_reduce_motion") private var reducedMotion = false
    @AppStorage("pulse_glass_enabled") private var glass = true
    @AppStorage("pulse_glass_motion") private var glassMotion = true
    @AppStorage("pulse_glass_tint") private var glassTint = 0.38
    init(store: PulseStore) { self.store = store; equalizer = store.equalizer }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Настройки").font(PulseTheme.display(34))
                    Text("Сделай Pulse своим.").font(PulseTheme.body(15)).foregroundStyle(PulseTheme.muted)
                }.padding(.bottom, 2)
                VStack(alignment: .leading, spacing: 18) {
                    Label("Оформление", systemImage: "circle.lefthalf.filled").font(PulseTheme.body(16, weight: .semibold))
                    Toggle("Стеклянные панели", isOn: $glass)
                    #if os(iOS)
                    Toggle("Блики при наклоне iPhone", isOn: $glassMotion).disabled(!glass || reducedMotion || systemReducedMotion)
                    Text("Мягкий свет на стекле следует за наклоном телефона.").font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted)
                    #endif
                    HStack { Text("Тонировка"); Slider(value: $glassTint, in: 0...1).accessibilityLabel("Тонировка стекла"); Text("\(Int(glassTint * 100))%").monospacedDigit().frame(width: 42) }.disabled(!glass)
                }.font(PulseTheme.body(14)).padding(22).pulseGlass(cornerRadius: 22)
                VStack(alignment: .leading, spacing: 18) {
                    Toggle("Эквалайзер", isOn: Binding(get: { equalizer.config.enabled }, set: equalizer.setEnabled)).font(PulseTheme.body(16, weight: .semibold))
                    Text("Твой баланс звука на этом устройстве").font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted)
                    PulseEQStatusView(playback: store.playback, equalizer: equalizer)
                    Picker("Звучание", selection: Binding(get: { equalizer.config.preset }, set: { id in if let preset = PulseEQPreset.all.first(where: { $0.id == id }) { equalizer.select(preset) } })) {
                        ForEach(PulseEQPreset.all) { Text($0.name).tag($0.id) }
                        Text("Свой баланс").tag("custom")
                    }
                    if let preset = PulseEQPreset.all.first(where: { $0.id == equalizer.config.preset }) { Text(preset.detail).font(PulseTheme.body(14)).foregroundStyle(PulseTheme.muted) }
                    eqCurve.frame(height: 90)
                    DisclosureGroup("Настроить вручную", isExpanded: $advancedEQ) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        ForEach(0..<10, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(Self.frequency(index)); Spacer(); Text(String(format: "%+.0f дБ", equalizer.config.safeGains[index])).monospacedDigit().foregroundStyle(PulseTheme.accent) }.font(PulseTheme.body(12))
                                Slider(value: Binding(get: { Double(equalizer.config.safeGains[index]) }, set: { equalizer.band(index, gain: Float($0)) }), in: -9...9, step: 0.5).disabled(!equalizer.config.enabled)
                            }
                        }
                    }
                    HStack { Button("Сбросить полосы") { equalizer.reset() }; Spacer(); Text("Запас уровня: \(Int(equalizer.config.headroomDB)) дБ").font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted) }
                    Text("При усилении полос уровень снижается автоматически, чтобы избежать перегрузки.").font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted)
                    }.font(PulseTheme.body(14)).padding(.top, 4)
                }.padding(24).pulseGlass(cornerRadius: 22)
                VStack(alignment: .leading, spacing: 20) {
                    Label("Воспроизведение и отклик", systemImage: "waveform").font(PulseTheme.body(16, weight: .semibold))
                    Toggle("Плавные переходы", isOn: $store.dj)
                    Toggle("Меньше анимаций", isOn: $reducedMotion)
                    #if os(iOS)
                    Toggle("Тактильный отклик", isOn: $haptics)
                    #endif
                    if systemReducedMotion { Text("Уменьшение движения включено — анимации интерфейса ограничены.").font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted) }
                    HStack { Image(systemName: "speaker.wave.2"); Slider(value: $store.volume, in: 0...1); Text("\(Int(store.volume * 100))%").font(PulseTheme.body(12).monospacedDigit()).frame(width: 36) }
                }.font(PulseTheme.body(14)).padding(22).pulseGlass(cornerRadius: 22)
                VStack(alignment: .leading, spacing: 12) {
                    Label("Медиатека в облаке", systemImage: "cloud").font(PulseTheme.body(16, weight: .semibold))
                    Text("Музыка и плейлисты всегда с тобой.").font(PulseTheme.body(14)).foregroundStyle(PulseTheme.muted)
                    DisclosureGroup("О синхронизации", isExpanded: $cloudDetails) {
                        Text("Медиатека, друзья и переписка общие с сайтом. Синхронизация идёт при запуске, возвращении в приложение и каждые 30 секунд.").font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted).padding(.top, 8)
                    }.font(PulseTheme.body(13))
                    Button("Обновить сейчас") { Task { await store.refresh() } }.disabled(store.syncing)
                    if !store.uploadStatus.isEmpty { Text(store.uploadStatus).font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted) }
                }.padding(22).pulseGlass(cornerRadius: 22)
                if store.signedIn { Button("Выйти из аккаунта", role: .destructive) { Task { await store.logout() } }.disabled(store.uploading).padding(.horizontal, 5) }
            }.font(PulseTheme.body(14)).padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(PulseAmbientBackground())
        .animation(systemReducedMotion || reducedMotion ? nil : .easeInOut(duration: 0.24), value: advancedEQ)
        .animation(systemReducedMotion || reducedMotion ? nil : .easeInOut(duration: 0.24), value: cloudDetails)
    }
    private static func frequency(_ index: Int) -> String { let value = PulseEQConfiguration.frequencies[index]; return value < 1000 ? "\(Int(value)) Гц" : "\(Int(value / 1000)) кГц" }
    private var eqCurve: some View {
        GeometryReader { geometry in
            ZStack {
                Path { path in let y = geometry.size.height / 2; path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y)) }.stroke(PulseTheme.line, style: StrokeStyle(lineWidth: 1, dash: [4,4]))
                Path { path in
                    for index in 0..<10 {
                        let point = CGPoint(x: geometry.size.width * Double(index) / 9, y: geometry.size.height / 2 - Double(equalizer.config.safeGains[index]) / 12 * geometry.size.height / 2)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }.stroke(PulseTheme.gradient, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }.padding(12).background(PulseTheme.raised, in: RoundedRectangle(cornerRadius: 14)).opacity(equalizer.config.enabled ? 1 : 0.35)
    }
}

private struct PulseEQStatusView: View {
    @ObservedObject var playback: PulsePlayback
    @ObservedObject var equalizer: PulseEqualizerSettings
    private var neutral: Bool { !equalizer.config.safeGains.contains { abs($0) > 0.001 } }
    var body: some View {
        Label(!equalizer.config.enabled ? "Эквалайзер выключен" : neutral ? "Нейтральный баланс · без коррекции" : playback.equalizerActive ? "Эквалайзер обрабатывает звук" : "Готов к воспроизведению", systemImage: playback.equalizerActive ? "waveform" : "slider.horizontal.3")
            .font(PulseTheme.body(12)).foregroundStyle(playback.equalizerActive ? PulseTheme.accent : PulseTheme.muted)
    }
}

import SwiftUI

struct PulseSettingsView: View {
    @ObservedObject var store: PulseStore
    @ObservedObject private var equalizer: PulseEqualizerSettings
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("pulse_reduce_motion") private var reducedMotion = false
    init(store: PulseStore) { self.store = store; equalizer = store.equalizer }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Твой звук.\nТвои правила.").font(PulseTheme.heading(36))
                VStack(alignment: .leading, spacing: 18) {
                    Toggle("Эквалайзер", isOn: Binding(get: { equalizer.config.enabled }, set: equalizer.setEnabled)).font(.headline)
                    Text("10 полос · настройки сохраняются на этом устройстве").font(.caption).foregroundStyle(PulseTheme.muted)
                    Picker("Звучание", selection: Binding(get: { equalizer.config.preset }, set: { id in if let preset = PulseEQPreset.all.first(where: { $0.id == id }) { equalizer.select(preset) } })) {
                        ForEach(PulseEQPreset.all) { Text($0.name).tag($0.id) }
                        Text("Свой баланс").tag("custom")
                    }
                    if let preset = PulseEQPreset.all.first(where: { $0.id == equalizer.config.preset }) { Text(preset.detail).font(.callout).foregroundStyle(PulseTheme.muted) }
                    eqCurve.frame(height: 90)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        ForEach(0..<10, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(Self.frequency(index)); Spacer(); Text(String(format: "%+.0f дБ", equalizer.config.safeGains[index])).monospacedDigit().foregroundStyle(PulseTheme.accent) }.font(.caption)
                                Slider(value: Binding(get: { Double(equalizer.config.safeGains[index]) }, set: { equalizer.band(index, gain: Float($0)) }), in: -9...9, step: 0.5).disabled(!equalizer.config.enabled)
                            }
                        }
                    }
                    HStack { Button("Сбросить полосы") { equalizer.reset() }; Spacer(); Text("Запас уровня: \(Int(equalizer.config.headroomDB)) дБ").font(.caption).foregroundStyle(PulseTheme.muted) }
                    Text("При усилении полос уровень автоматически снижается, чтобы уменьшить риск перегрузки. Выбирай пресет под свои наушники и музыку.").font(.caption).foregroundStyle(PulseTheme.muted)
                }.padding(22).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 22))
                VStack(spacing: 18) {
                    Toggle("DJ · плавные переходы", isOn: $store.dj)
                    Toggle("Меньше анимаций", isOn: $reducedMotion)
                    if systemReducedMotion { Text("Уменьшение движения включено — анимации интерфейса ограничены.").font(.caption).foregroundStyle(PulseTheme.muted) }
                    HStack { Image(systemName: "speaker.wave.2"); Slider(value: $store.volume, in: 0...1); Text("\(Int(store.volume * 100))%").font(.caption.monospacedDigit()).frame(width: 36) }
                }.font(.callout).padding(22).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .leading, spacing: 12) {
                    Label("Медиатека в облаке", systemImage: "cloud").font(.headline)
                    Text("Аккаунт, музыка, друзья и сообщения общие с сайтом. Медиатека обновляется при запуске, возвращении в приложение и каждые 30 секунд.").font(.callout).foregroundStyle(PulseTheme.muted)
                    Button("Обновить сейчас") { Task { await store.refresh() } }.disabled(store.syncing)
                    if !store.uploadStatus.isEmpty { Text(store.uploadStatus).font(.caption).foregroundStyle(PulseTheme.muted) }
                }.padding(22).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 22))
                if store.signedIn { Button("Выйти из аккаунта", role: .destructive) { Task { await store.logout() } }.disabled(store.uploading).padding(.horizontal, 5) }
            }.padding(20)
        }.background(PulseTheme.background)
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

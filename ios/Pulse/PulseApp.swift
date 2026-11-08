import SwiftUI

@main
struct PulseApp: App {
    @StateObject private var store = PulseStore()
    @Environment(\.scenePhase) private var phase
    init() { PulseTheme.registerFonts() }
    var body: some Scene {
        WindowGroup("Pulse") {
            PulseRootView()
                .environmentObject(store)
                #if os(macOS)
                .background(PulseTouchBarHost(store: store).frame(width: 0, height: 0))
                #endif
                .preferredColorScheme(.dark)
                .tint(PulseTheme.accent)
                .task { await store.start() }
                .onChange(of: phase) { _, value in
                    if value == .active { Task { await store.refresh() } }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Обновить медиатеку") { Task { await store.refresh() } }.keyboardShortcut("r")
                Button("Воспроизвести / пауза") { store.togglePlayback() }.keyboardShortcut(.space, modifiers: [])
            }
        }
        #endif
    }
}

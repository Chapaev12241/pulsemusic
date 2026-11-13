import SwiftUI
import CoreText

enum PulseTheme {
    static let background = Color(red: 0.031, green: 0.031, blue: 0.039)
    static let panel = Color(red: 0.067, green: 0.067, blue: 0.082)
    static let raised = Color(red: 0.105, green: 0.105, blue: 0.125)
    static let line = Color.white.opacity(0.075)
    static let accent = Color(red: 0.65, green: 0.60, blue: 1)
    static let muted = Color(red: 0.64, green: 0.63, blue: 0.69)
    static let gradient = LinearGradient(colors: [Color(red: 0.74, green: 0.67, blue: 1), accent, Color(red: 0.53, green: 0.70, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static func heading(_ size: CGFloat) -> Font { .custom("Soledago", size: size) }
    static func registerFonts() {
        for name in ["Soledago", "Docker One"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }
}
struct PulsePrimaryVisual: ButtonStyle {
    @Environment(\.pulseReducedMotion) private var reducedMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.black.opacity(0.9))
            .padding(.horizontal, 20).frame(minHeight: 44).background(PulseTheme.gradient, in: RoundedRectangle(cornerRadius: 13))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .overlay(PulseGlassRim(radius: 13))
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.97 : 1)
            .animation(reducedMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
struct PulseIconVisual: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(width: 40, height: 40).foregroundStyle(PulseTheme.muted)
            .background(configuration.isPressed ? PulseTheme.raised.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 14))
            .pulseGlass(cornerRadius: 14)
            .contentShape(Rectangle())
    }
}

private struct PulseReducedMotionKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var pulseReducedMotion: Bool { get { self[PulseReducedMotionKey.self] } set { self[PulseReducedMotionKey.self] = newValue } }
}

struct PulseHeartButton: View {
    @ObservedObject var store: PulseStore
    let track: PulseTrack
    @Environment(\.pulseReducedMotion) private var reducedMotion
    private var liked: Bool { store.state.liked.contains(track.id) }
    var body: some View {
        Button { store.like(track) } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .foregroundStyle(liked ? PulseTheme.accent : PulseTheme.muted)
                .scaleEffect(liked && !reducedMotion ? 1.12 : 1)
                .animation(reducedMotion ? nil : .spring(response: 0.25, dampingFraction: 0.55), value: liked)
                .frame(width: 32, height: 40)
        }.buttonStyle(PulseTactileButton(feedback: .favorite)).accessibilityLabel("Избранное: \(track.title)")
    }
}

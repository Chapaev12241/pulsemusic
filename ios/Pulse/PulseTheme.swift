import SwiftUI
import CoreText

enum PulseTheme {
    static let background = Color(red: 8/255, green: 9/255, blue: 13/255)
    static let panel = Color(red: 20/255, green: 22/255, blue: 29/255)
    static let raised = Color(red: 32/255, green: 35/255, blue: 45/255)
    static let text = Color(red: 243/255, green: 244/255, blue: 248/255)
    static let line = Color.white.opacity(0.065)
    static let accent = Color(red: 183/255, green: 170/255, blue: 246/255)
    static let muted = Color(red: 156/255, green: 159/255, blue: 174/255)
    static let gradient = LinearGradient(colors: [Color(red: 0.80, green: 0.76, blue: 1), accent], startPoint: .topLeading, endPoint: .bottomTrailing)
    // The custom display face belongs to the brand, while UI stays legible.
    static func heading(_ size: CGFloat) -> Font { .custom("Soledago", size: size) }
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(weight == .bold || weight == .heavy ? "HelveticaNeue-Bold" : weight == .semibold || weight == .medium ? "HelveticaNeue-Medium" : "HelveticaNeue", size: size, relativeTo: .body)
    }
    static func display(_ size: CGFloat) -> Font { .custom("HelveticaNeue-Medium", size: size, relativeTo: .largeTitle) }
    static func registerFonts() {
        for name in ["Soledago", "Docker One"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }
}
struct PulsePrimaryVisual: ButtonStyle {
    @Environment(\.pulseReducedMotion) private var reducedMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(PulseTheme.body(15, weight: .semibold)).foregroundStyle(Color.black.opacity(0.9))
            .padding(.horizontal, 20).frame(minHeight: 48).background(PulseTheme.gradient, in: RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .overlay(PulseGlassRim(radius: 18))
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.97 : 1)
            .animation(reducedMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
struct PulseIconVisual: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(width: 44, height: 44).foregroundStyle(PulseTheme.muted)
            .background(configuration.isPressed ? PulseTheme.raised.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 14))
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

struct PulsePressVisual: ButtonStyle {
    @Environment(\.pulseReducedMotion) private var reducedMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.975 : 1)
            .animation(reducedMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

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
struct PulsePrimaryButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.black.opacity(0.9))
            .padding(.horizontal, 20).frame(minHeight: 44).background(PulseTheme.gradient, in: RoundedRectangle(cornerRadius: 13))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.97 : 1)
            .animation(reducedMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
struct PulseIconButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(width: 40, height: 40).foregroundStyle(PulseTheme.muted)
            .background(configuration.isPressed ? PulseTheme.raised : .clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
    }
}

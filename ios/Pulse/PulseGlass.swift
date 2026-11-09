import SwiftUI

struct PulseAmbientBackground: View {
    @AppStorage("pulse_glass_enabled") private var glass = true
    var body: some View {
        ZStack {
            PulseTheme.background
            if glass {
                RadialGradient(colors: [PulseTheme.accent.opacity(0.19), .clear], center: .topLeading, startRadius: 0, endRadius: 560)
                RadialGradient(colors: [Color(red: 0.22, green: 0.40, blue: 0.8).opacity(0.13), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 500)
            }
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}

struct PulseGlassBackground: View {
    var radius: CGFloat
    @AppStorage("pulse_glass_enabled") private var enabled = true
    @AppStorage("pulse_glass_tint") private var tint = 0.38
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    var body: some View {
        Group {
            if enabled && !reduceTransparency {
                material
                    .overlay { shape.fill(Color.black.opacity(0.12 + min(1, max(0, tint.isFinite ? tint : 0.38)) * 0.36)) }
                    .overlay { shape.fill(LinearGradient(colors: [.white.opacity(0.06), .clear, PulseTheme.accent.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing)) }
            } else { shape.fill(PulseTheme.panel) }
        }.allowsHitTesting(false)
    }
    @ViewBuilder private var material: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(PulseTheme.accent.opacity(0.06)), in: shape)
        } else { shape.fill(.ultraThinMaterial) }
        #else
        shape.fill(.ultraThinMaterial)
        #endif
    }
}

struct PulseGlassRim: View {
    var radius: CGFloat
    @ObservedObject private var motion = PulseGlassMotion.shared
    @AppStorage("pulse_glass_enabled") private var enabled = true
    @Environment(\.pulseReducedMotion) private var reducedMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var light: CGPoint { reducedMotion || reduceTransparency ? .zero : motion.tilt }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let angle = Double(light.x * 85 + light.y * 55)
        ZStack {
            shape.strokeBorder(Color.white.opacity(enabled ? 0.1 : 0.06), lineWidth: 1)
            if enabled && !reduceTransparency {
                shape.strokeBorder(AngularGradient(stops: [
                    .init(color: .white.opacity(0.8), location: 0),
                    .init(color: PulseTheme.accent.opacity(0.25), location: 0.12),
                    .init(color: .clear, location: 0.27),
                    .init(color: .white.opacity(0.06), location: 0.45),
                    .init(color: Color.blue.opacity(0.45), location: 0.6),
                    .init(color: .clear, location: 0.78),
                    .init(color: .white.opacity(0.8), location: 1)
                ], center: UnitPoint(x: 0.5 + light.x * 0.25, y: 0.5 + light.y * 0.25), angle: .degrees(-55 + angle)), lineWidth: 1.2)
                    .blendMode(.screen)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct PulseGlassPanel: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.background(PulseGlassBackground(radius: radius))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(PulseGlassRim(radius: radius))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 7)
    }
}
extension View {
    func pulseGlass(cornerRadius: CGFloat = 22) -> some View { modifier(PulseGlassPanel(radius: cornerRadius)) }
}

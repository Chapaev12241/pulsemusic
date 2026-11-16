import SwiftUI

struct PulseAmbientBackground: View {
    @AppStorage("pulse_glass_enabled") private var glass = true
    var body: some View {
        PulseTheme.background.ignoresSafeArea().allowsHitTesting(false)
    }
}

enum PulseGlassStyle { case card, hero, chrome }

struct PulseGlassBackground: View {
    var radius: CGFloat
    var style: PulseGlassStyle = .card
    @AppStorage("pulse_glass_enabled") private var enabled = true
    @AppStorage("pulse_glass_tint") private var tint = 0.38
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    var body: some View {
        Group {
            if enabled && !reduceTransparency {
                surface
                    .overlay { shape.fill(Color.black.opacity(0.12 + min(1, max(0, tint.isFinite ? tint : 0.38)) * 0.36)) }
                    .overlay { shape.fill(LinearGradient(colors: [.white.opacity(0.025), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)) }
            } else { shape.fill(PulseTheme.panel) }
        }.allowsHitTesting(false)
    }
    @ViewBuilder private var surface: some View {
        if style == .chrome { material }
        else { shape.fill(PulseTheme.panel) }
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

// Ordinary cards never subscribe to sensor ticks. Only the hero and fixed
// transport chrome mount a moving rim, keeping scrolling independent of motion.
struct PulseGlassRim: View {
    var radius: CGFloat
    var tracksMotion = false
    @AppStorage("pulse_glass_enabled") private var enabled = true
    @AppStorage("pulse_glass_motion") private var motionEnabled = true
    @Environment(\.pulseReducedMotion) private var reducedMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Group {
            if tracksMotion && enabled && motionEnabled && !reducedMotion && !reduceTransparency {
                PulseMovingGlassRim(radius: radius)
            } else { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(PulseTheme.line, lineWidth: 1) }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
private struct PulseMovingGlassRim: View {
    let radius: CGFloat
    @ObservedObject private var motion = PulseGlassMotion.shared
    var body: some View { PulseGlassStroke(radius: radius, light: motion.tilt, bright: true) }
}
private struct PulseGlassStroke: View {
    let radius: CGFloat
    let light: CGPoint
    let bright: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let angle = Double(light.x * 85 + light.y * 55)
        shape.strokeBorder(AngularGradient(stops: [
            .init(color: .white.opacity(bright ? 0.28 : 0.08), location: 0),
            .init(color: PulseTheme.accent.opacity(bright ? 0.14 : 0.06), location: 0.15),
            .init(color: .white.opacity(0.04), location: 0.3),
            .init(color: .white.opacity(0.07), location: 0.48),
            .init(color: Color.blue.opacity(bright ? 0.18 : 0.05), location: 0.62),
            .init(color: .white.opacity(0.06), location: 0.8),
            .init(color: .white.opacity(bright ? 0.28 : 0.08), location: 1)
        ], center: UnitPoint(x: 0.5 + light.x * 0.25, y: 0.5 + light.y * 0.25), angle: .degrees(-55 + angle)), lineWidth: 1)
    }
}

private struct PulseGlassPanel: ViewModifier {
    let radius: CGFloat
    let style: PulseGlassStyle
    func body(content: Content) -> some View {
        content.background(PulseGlassBackground(radius: radius, style: style))
            .overlay(PulseGlassRim(radius: radius, tracksMotion: style != .card))
    }
}
extension View {
    func pulseGlass(cornerRadius: CGFloat = 22, style: PulseGlassStyle = .card) -> some View { modifier(PulseGlassPanel(radius: cornerRadius, style: style)) }
}

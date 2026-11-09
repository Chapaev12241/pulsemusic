import SwiftUI
#if os(iOS)
import CoreMotion
import UIKit
#endif

@MainActor
protocol PulseMotionSource: AnyObject {
    var available: Bool { get }
    func start(_ receive: @escaping (CGPoint?) -> Void)
    func stop()
}

enum PulseGlassTilt {
    static func normalized(_ point: CGPoint, relativeTo baseline: CGPoint) -> CGPoint {
        guard point.x.isFinite, point.y.isFinite, baseline.x.isFinite, baseline.y.isFinite else { return .zero }
        return CGPoint(x: min(1, max(-1, (point.x - baseline.x) * 2.4)), y: min(1, max(-1, (point.y - baseline.y) * 2.4)))
    }
}

// Shared independently of PulseStore: sensor ticks only invalidate glass rims,
// never the library, playback clock or the content inside each panel.
@MainActor
final class PulseGlassMotion: ObservableObject {
    #if os(iOS)
    static let shared = PulseGlassMotion(source: PulseDeviceMotionSource())
    #else
    static let shared = PulseGlassMotion()
    #endif
    @Published private(set) var tilt = CGPoint.zero
    private(set) var active = false
    private let source: PulseMotionSource?
    private var baseline: CGPoint?
    private var generation = 0
    init(source: PulseMotionSource? = nil) { self.source = source }
    func setEnabled(_ enabled: Bool) {
        let next = enabled && source?.available == true
        guard next != active else { return }
        generation += 1; let stamp = generation
        active = next; baseline = nil
        if next {
            source?.start { [weak self] point in
                guard let self, self.active, self.generation == stamp else { return }
                guard let point else { self.setEnabled(false); return }
                guard point.x.isFinite, point.y.isFinite else { return }
                if self.baseline == nil { self.baseline = point }
                let target = PulseGlassTilt.normalized(point, relativeTo: self.baseline ?? point)
                let value = CGPoint(x: self.tilt.x * 0.65 + target.x * 0.35, y: self.tilt.y * 0.65 + target.y * 0.35)
                // Ignore hand tremor instead of invalidating every visible rim.
                if abs(value.x - self.tilt.x) + abs(value.y - self.tilt.y) > 0.025 { self.tilt = value }
            }
        } else { source?.stop(); if tilt != .zero { tilt = .zero } }
    }
}

#if os(iOS)
@MainActor
private final class PulseDeviceMotionSource: PulseMotionSource {
    private let manager = CMMotionManager()
    var available: Bool { manager.isDeviceMotionAvailable }
    func start(_ receive: @escaping (CGPoint?) -> Void) {
        guard available else { receive(nil); return }
        manager.deviceMotionUpdateInterval = 1.0 / 15
        manager.startDeviceMotionUpdates(to: .main) { motion, error in
            guard error == nil, let motion else { receive(nil); return }
            // Device-frame gravity is fused from the gyro and accelerometer;
            // transient acceleration doesn't throw the highlight across a panel.
            receive(CGPoint(x: motion.gravity.x, y: -motion.gravity.y))
        }
    }
    func stop() { manager.stopDeviceMotionUpdates() }
    deinit { manager.stopDeviceMotionUpdates() }
}
#endif

struct PulseGlassLifecycle: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.pulseReducedMotion) private var reducedMotion
    @Environment(\.accessibilityReduceTransparency) private var reducedTransparency
    @AppStorage("pulse_glass_enabled") private var glass = true
    @AppStorage("pulse_glass_motion") private var motion = true
    private var enabled: Bool { phase == .active && glass && motion && !reducedMotion && !reducedTransparency }
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task(id: enabled) { PulseGlassMotion.shared.setEnabled(enabled) }
            .onDisappear { PulseGlassMotion.shared.setEnabled(false) }
    }
}

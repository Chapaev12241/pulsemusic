import SwiftUI
#if os(iOS)
import UIKit
#endif

enum PulseFeedbackKind: Sendable { case tap, transport, track, favorite, shuffle, navigation, seekEnd }
struct PulseScrubFeedbackGate {
    private(set) var active = false
    private var position = 0.0
    private var lastPulse = -Double.infinity
    mutating func begin(at value: Double) { active = true; position = value; lastPulse = -.infinity }
    mutating func end() { active = false }
    mutating func moved(to value: Double, now: Double) -> Bool {
        guard active, value.isFinite, now.isFinite, abs(value - position) >= 0.04, now - lastPulse >= 0.06 else { return false }
        position = value; lastPulse = now; return true
    }
}
enum PulseHaptics {
    static func fire(_ kind: PulseFeedbackKind) {
        #if os(iOS)
        Task { @MainActor in PulseHapticDriver.shared.fire(kind) }
        #endif
    }
    static func beginScrub(at value: Double) {
        #if os(iOS)
        Task { @MainActor in PulseHapticDriver.shared.begin(at: value) }
        #endif
    }
    static func scrub(to value: Double) {
        #if os(iOS)
        Task { @MainActor in PulseHapticDriver.shared.scrub(to: value) }
        #endif
    }
    static func endScrub(completed: Bool = true) {
        #if os(iOS)
        Task { @MainActor in PulseHapticDriver.shared.end(completed: completed) }
        #endif
    }
}
#if os(iOS)
@MainActor
private final class PulseHapticDriver {
    static let shared = PulseHapticDriver()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private var gate = PulseScrubFeedbackGate()
    private var lastFeedback = -Double.infinity
    private var enabled: Bool { UIApplication.shared.applicationState == .active && UserDefaults.standard.object(forKey: "pulse_haptics") as? Bool != false }
    func fire(_ kind: PulseFeedbackKind) {
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFeedback >= 0.04 else { return }; lastFeedback = now
        switch kind {
        case .tap: light.impactOccurred(intensity: 0.24); light.prepare()
        case .transport: rigid.impactOccurred(intensity: 0.38); rigid.prepare()
        case .track: medium.impactOccurred(intensity: 0.60); medium.prepare()
        case .favorite: soft.impactOccurred(intensity: 0.50); soft.prepare()
        case .shuffle, .navigation: selection.selectionChanged(); selection.prepare()
        case .seekEnd: soft.impactOccurred(intensity: 0.12); soft.prepare()
        }
    }
    func begin(at value: Double) { gate.begin(at: value); if enabled { soft.prepare() } }
    func scrub(to value: Double) {
        guard enabled, gate.moved(to: value, now: ProcessInfo.processInfo.systemUptime) else { return }
        soft.impactOccurred(intensity: 0.08); soft.prepare()
    }
    func end(completed: Bool) { let wasActive = gate.active; gate.end(); if completed && wasActive { fire(.seekEnd) } }
}
#endif

struct PulseTactileButton: PrimitiveButtonStyle {
    var feedback: PulseFeedbackKind? = .tap
    func makeBody(configuration: Configuration) -> some View {
        Button { if let feedback { PulseHaptics.fire(feedback) }; configuration.trigger() } label: { configuration.label }.buttonStyle(.plain)
    }
}
struct PulsePrimaryButton: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { PulseHaptics.fire(.transport); configuration.trigger() } label: { configuration.label }.buttonStyle(PulsePrimaryVisual())
    }
}
struct PulseIconButton: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { PulseHaptics.fire(.tap); configuration.trigger() } label: { configuration.label }.buttonStyle(PulseIconVisual())
    }
}

import SwiftUI

@MainActor
final class PulseBeat: ObservableObject {
    @Published private(set) var strength = 0.0
    func receive(_ level: Double) {
        let target = level.isFinite ? min(1, max(0, level)) : 0
        let next = strength * (target > strength ? 0.25 : 0.72) + target * (target > strength ? 0.75 : 0.28)
        if abs(next - strength) > 0.003 { strength = next } else if target == 0 && strength != 0 { strength = 0 }
    }
}

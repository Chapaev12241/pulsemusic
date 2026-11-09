import SwiftUI

@MainActor
final class PulseSwipeMotion: ObservableObject {
    @Published var offset: CGFloat = 0
    @Published private(set) var committing = false
    var direction: Int { offset <= 0 ? 1 : -1 }
    func drag(_ value: DragGesture.Value, excluding: CGRect = .null) {
        guard !committing, !excluding.insetBy(dx: -8, dy: -8).contains(value.startLocation),
              abs(value.translation.width) > abs(value.translation.height) * 1.6 else { return }
        offset = value.translation.width
    }
    func end(_ value: DragGesture.Value, width: CGFloat, reducedMotion: Bool, excluding: CGRect = .null, action: @escaping (Int) -> Void) {
        guard !committing else { return }
        let direction = PulseTrackSwipe.direction(horizontal: value.translation.width, vertical: value.translation.height, start: value.startLocation, excluding: excluding)
            ?? (abs(value.translation.width) > 24 ? PulseTrackSwipe.direction(horizontal: value.predictedEndTranslation.width, vertical: value.predictedEndTranslation.height, start: value.startLocation, excluding: excluding) : nil)
        if let direction { advance(direction, width: width, reducedMotion: reducedMotion, action: action) }
        else { withAnimation(reducedMotion ? nil : .spring(response: 0.38, dampingFraction: 0.74)) { offset = 0 } }
    }
    func advance(_ direction: Int, width: CGFloat, reducedMotion: Bool, action: @escaping (Int) -> Void) {
        guard !committing else { return }
        if reducedMotion { offset = 0; action(direction); return }
        committing = true
        withAnimation(.easeIn(duration: 0.2), completionCriteria: .logicallyComplete) {
            offset = (direction > 0 ? -1 : 1) * max(380, width) * 1.35
        } completion: {
            action(direction)
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { self.offset = 0; self.committing = false }
        }
    }
}

struct PulseSwipeDeck<Card: View>: View {
    @ObservedObject var motion: PulseSwipeMotion
    let current: PulseTrack?
    let incoming: (Int) -> PulseTrack?
    let width: CGFloat
    let reducedMotion: Bool
    @ViewBuilder let card: (PulseTrack?) -> Card
    var body: some View {
        let progress = min(1, abs(motion.offset) / max(1, width * 0.65))
        ZStack {
            if abs(motion.offset) > 0.5, !reducedMotion {
                card(incoming(motion.direction)).scaleEffect(0.9 + progress * 0.1).offset(y: (1 - progress) * 18)
                    .opacity(0.45 + progress * 0.55).accessibilityHidden(true)
            }
            card(current)
                .rotationEffect(.degrees(reducedMotion ? 0 : Double(motion.offset / max(1, width)) * 13), anchor: .bottom)
                .offset(x: reducedMotion ? 0 : motion.offset, y: reducedMotion ? 0 : -min(16, abs(motion.offset) * 0.035))
                .opacity(reducedMotion ? 1 : max(0, 1 - max(0, progress - 0.6) * 0.65))
                .shadow(color: .black.opacity(progress * 0.25), radius: 20, y: 10)
        }
    }
}

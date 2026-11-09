import SwiftUI

struct PulseLyricWordsView: View {
    @ObservedObject var playback: PulsePlayback
    let words: [PulseLyricWord]
    @Environment(\.pulseReducedMotion) private var reducedMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: playback.paused || playback.buffering || reducedMotion)) { _ in
            let time = reducedMotion ? playback.time : playback.interpolatedTime
            PulseWordFlow(spacing: 6, lineSpacing: 5) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    let progress = min(1, max(0, (time - word.start) / max(0.04, word.end - word.start)))
                    Text(word.text).foregroundStyle(Color.white.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Text(word.text).foregroundStyle(.white)
                                .mask(alignment: .leading) { GeometryReader { proxy in Rectangle().frame(width: proxy.size.width * progress) } }
                        }
                        .scaleEffect(!reducedMotion && progress > 0 && progress < 1 ? 1.035 : 1)
                }
            }.font(.system(size: 24, weight: .semibold))
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(words.map(\.text).joined(separator: " "))
    }
}

// Layout wraps whole words without inserting manual line breaks at a fixed size.
struct PulseWordFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    private func positions(width: CGFloat, subviews: Subviews) -> (CGSize, [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, used: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + lineSpacing; row = 0 }
            points.append(CGPoint(x: x, y: y)); used = max(used, x + size.width)
            x += size.width + spacing; row = max(row, size.height)
        }
        return (CGSize(width: min(width, used), height: y + row), points)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        positions(width: proposal.width ?? 600, subviews: subviews).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = positions(width: bounds.width, subviews: subviews)
        for (index, point) in result.1.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }
}

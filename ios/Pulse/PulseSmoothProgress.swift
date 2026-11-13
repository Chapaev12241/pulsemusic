#if os(iOS)
import SwiftUI
import UIKit

// The compositor interpolates the small progress layer; the library stays on its 4 Hz audio clock.
struct PulseSmoothProgress: UIViewRepresentable {
    let time: Double, duration: Double
    let trackID: String
    let playing: Bool
    func makeUIView(context: Context) -> PulseProgressLayerView { PulseProgressLayerView() }
    func updateUIView(_ view: PulseProgressLayerView, context: Context) { view.update(time: time, duration: duration, id: trackID, playing: playing) }
    static func dismantleUIView(_ view: PulseProgressLayerView, coordinator: ()) { view.stop() }
}
final class PulseProgressLayerView: UIView {
    private let fill = CALayer()
    private var trackID: String?
    private var reference = 0.0, timestamp = 0.0, length = -1.0
    private var advancing = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.backgroundColor = UIColor(red: 0.65, green: 0.60, blue: 1, alpha: 1).cgColor
        fill.cornerRadius = 1.5
        layer.addSublayer(fill)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fill.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        fill.position = CGPoint(x: 0, y: bounds.midY)
        CATransaction.commit()
    }
    func update(time: Double, duration: Double, id: String, playing: Bool) {
        let time = time.isFinite ? max(0, time) : 0, duration = duration.isFinite ? max(0, duration) : 0
        let now = CACurrentMediaTime(), estimate = reference + (advancing ? now - timestamp : 0)
        guard trackID != id || abs(length - duration) > 0.1 || advancing != playing || abs(estimate - time) > 0.65 else { return }
        trackID = id; reference = time; timestamp = now; length = duration; advancing = playing
        fill.removeAnimation(forKey: "progress")
        let ratio = duration > 0 ? min(1, time / duration) : 0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fill.transform = CATransform3DMakeScale(CGFloat(playing && duration > time ? 1 : ratio), 1, 1)
        CATransaction.commit()
        if playing && duration > time {
            let animation = CABasicAnimation(keyPath: "transform.scale.x")
            animation.fromValue = ratio; animation.toValue = 1
            animation.duration = duration - time
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            fill.add(animation, forKey: "progress")
        }
    }
    func stop() { fill.removeAllAnimations() }
}
#endif

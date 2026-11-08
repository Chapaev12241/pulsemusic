#if os(macOS)
import SwiftUI
import AppKit
import Combine

// Attach to the window rather than a focusable SwiftUI child: playback controls
// remain available while navigating the app, without stealing keyboard focus.
struct PulseTouchBarHost: NSViewRepresentable {
    let store: PulseStore
    func makeCoordinator() -> PulseTouchBarController { PulseTouchBarController(store: store) }
    func makeNSView(context: Context) -> PulseTouchBarAttachment {
        let view = PulseTouchBarAttachment()
        view.controller = context.coordinator
        return view
    }
    func updateNSView(_ view: PulseTouchBarAttachment, context: Context) { context.coordinator.refresh() }
    static func dismantleNSView(_ view: PulseTouchBarAttachment, coordinator: PulseTouchBarController) { coordinator.detach() }
}

final class PulseTouchBarAttachment: NSView {
    weak var controller: PulseTouchBarController?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { controller?.attach(to: window) }
        else { controller?.detach() }
    }
}

@MainActor
final class PulseTouchBarController: NSObject, NSTouchBarDelegate {
    enum Item {
        static let previous = NSTouchBarItem.Identifier("com.chapaev12241.pulse.previous")
        static let play = NSTouchBarItem.Identifier("com.chapaev12241.pulse.play")
        static let next = NSTouchBarItem.Identifier("com.chapaev12241.pulse.next")
        static let like = NSTouchBarItem.Identifier("com.chapaev12241.pulse.like")
        static let volume = NSTouchBarItem.Identifier("com.chapaev12241.pulse.volume")
    }
    let store: PulseStore
    let bar = NSTouchBar()
    private weak var window: NSWindow?
    private var previousBar: NSTouchBar?
    private var subscription: AnyCancellable?
    private var buttons: [NSTouchBarItem.Identifier: NSButton] = [:]
    private var volumeSlider: NSSlider?

    init(store: PulseStore) {
        self.store = store
        super.init()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Item.previous, Item.play, Item.next, Item.like, Item.volume]
        bar.principalItemIdentifier = Item.play
        subscription = store.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.refresh() }
    }
    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        detach()
        self.window = window
        previousBar = window.touchBar
        window.touchBar = bar
        refresh()
    }
    func detach() {
        if window?.touchBar === bar { window?.touchBar = previousBar }
        window = nil; previousBar = nil
    }
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        if identifier == Item.volume {
            let slider = NSSlider(value: store.volume, minValue: 0, maxValue: 1, target: self, action: #selector(changeVolume(_:)))
            slider.setAccessibilityLabel("Громкость Pulse")
            slider.widthAnchor.constraint(equalToConstant: 120).isActive = true
            slider.isContinuous = true
            let image = NSImageView(image: NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Громкость")!)
            image.widthAnchor.constraint(equalToConstant: 18).isActive = true
            let stack = NSStackView(views: [image, slider]); stack.orientation = .horizontal; stack.spacing = 8
            item.view = stack; volumeSlider = slider
        } else {
            let spec: (String, String, Selector)
            switch identifier {
            case Item.previous: spec = ("backward.end.fill", "Предыдущий трек", #selector(previousTrack))
            case Item.play: spec = ("play.fill", "Воспроизвести", #selector(togglePlayback))
            case Item.next: spec = ("forward.end.fill", "Следующий трек", #selector(nextTrack))
            case Item.like: spec = ("heart", "Избранное", #selector(toggleLike))
            default: return nil
            }
            let button = NSButton(image: NSImage(systemSymbolName: spec.0, accessibilityDescription: spec.1)!, target: self, action: spec.2)
            button.setAccessibilityLabel(spec.1)
            button.widthAnchor.constraint(equalToConstant: identifier == Item.play ? 70 : 46).isActive = true
            if identifier == Item.play { button.bezelColor = NSColor(calibratedRed: 0.57, green: 0.46, blue: 0.91, alpha: 1) }
            item.view = button; buttons[identifier] = button
        }
        refresh()
        return item
    }
    func refresh() {
        let hasTrack = store.currentTrack != nil
        buttons[Item.play]?.isEnabled = hasTrack || !store.tracks.isEmpty
        buttons[Item.previous]?.isEnabled = hasTrack
        buttons[Item.next]?.isEnabled = hasTrack
        let playLabel = store.paused ? "Воспроизвести" : "Пауза"
        buttons[Item.play]?.image = NSImage(systemSymbolName: store.paused ? "play.fill" : "pause.fill", accessibilityDescription: playLabel)
        buttons[Item.play]?.setAccessibilityLabel(playLabel)
        let liked = store.currentTrack.map { store.state.liked.contains($0.id) } ?? false
        buttons[Item.like]?.image = NSImage(systemSymbolName: liked ? "heart.fill" : "heart", accessibilityDescription: "Избранное")
        buttons[Item.like]?.isEnabled = hasTrack && store.signedIn
        if let volumeSlider, abs(volumeSlider.doubleValue - store.volume) > 0.001 { volumeSlider.doubleValue = store.volume }
    }
    @objc func previousTrack() { store.next(-1) }
    @objc func nextTrack() { store.next(1) }
    @objc func togglePlayback() {
        if store.currentTrack == nil, let first = store.tracks.first { store.play(first, within: store.tracks) }
        else { store.togglePlayback() }
    }
    @objc func toggleLike() { if store.signedIn, let track = store.currentTrack { store.like(track) } }
    @objc func changeVolume(_ slider: NSSlider) { store.volume = min(1, max(0, slider.doubleValue)) }
}
#endif

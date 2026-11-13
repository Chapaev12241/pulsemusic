#if os(macOS)
import SwiftUI
import AppKit

struct PulseMacWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> PulseWindowSurface { PulseWindowSurface() }
    func updateNSView(_ view: PulseWindowSurface, context: Context) { view.configure() }
}
final class PulseWindowSurface: NSView {
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
    func configure() {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}
#endif

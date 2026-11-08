import AppKit
import Foundation

let root = "ios/Pulse/MacAssets.xcassets/AppIcon.appiconset"
let files = try FileManager.default.contentsOfDirectory(atPath: root).filter { $0.hasSuffix(".png") }
precondition(files.count == 10, "Expected all ten Mac icon representations")
for name in files {
    let data = try Data(contentsOf: URL(fileURLWithPath: root + "/" + name))
    guard let image = NSBitmapImageRep(data: data) else { fatalError("Unreadable icon: \(name)") }
    let w = image.pixelsWide, h = image.pixelsHigh
    precondition(w == h && image.hasAlpha, "Icon must be square RGBA: \(name)")
    for (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)] {
        precondition((image.colorAt(x: x, y: y)?.alphaComponent ?? 1) < 0.01, "Square corner found in \(name)")
    }
    precondition((image.colorAt(x: w / 2, y: h / 2)?.alphaComponent ?? 0) > 0.99, "Missing center in \(name)")
}
print("PASS: all 10 Mac icons have transparent corners and an opaque center")

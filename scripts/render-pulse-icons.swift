import AppKit
import Foundation

// A geometric master exports each platform variant without raster resampling.
struct Shape {
    let rect: CGRect
    let radius: CGFloat
    let color: String
    let ellipse: Bool
    init(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat = 0, _ color: String, ellipse: Bool = false) {
        rect = CGRect(x: x, y: y, width: w, height: h); self.radius = radius; self.color = color; self.ellipse = ellipse
    }
    var svg: String {
        if ellipse { return "<ellipse cx=\"\(rect.midX)\" cy=\"\(rect.midY)\" rx=\"\(rect.width / 2)\" ry=\"\(rect.height / 2)\" fill=\"\(color)\"/>" }
        return "<rect x=\"\(rect.minX)\" y=\"\(rect.minY)\" width=\"\(rect.width)\" height=\"\(rect.height)\" rx=\"\(radius)\" fill=\"\(color)\"/>"
    }
    func draw(_ context: CGContext) {
        let hex = UInt32(color.dropFirst(), radix: 16)!
        context.setFillColor(NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1).cgColor)
        if ellipse { context.fillEllipse(in: rect) }
        else { context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)); context.fillPath() }
    }
}
let ink = "#101314", lavender = "#C2B4F8"
let mark = [Shape(84, 84, 344, 344, 0, lavender, ellipse: true),
            Shape(188, 166, 52, 196, 26, ink),
            Shape(188, 166, 148, 144, 26, ink),
            Shape(232, 206, 60, 60, 0, lavender, ellipse: true)]
enum Variant { case app, mac, windows }
func layout(_ variant: Variant) -> (Shape, CGFloat, CGFloat) {
    switch variant {
    case .app: return (Shape(0, 0, 512, 512, 0, ink), 0, 1)
    case .mac: return (Shape(50, 50, 412, 412, 92, ink), 50, 412 / 512)
    case .windows: return (Shape(4, 4, 504, 504, 112, ink), 4, 504 / 512)
    }
}
func writeSVG(_ path: String, variant: Variant, canvas: Int = 512) throws {
    let (base, inset, scale) = layout(variant)
    let content = base.svg + "<g transform=\"translate(\(inset) \(inset)) scale(\(scale))\">" + mark.map(\.svg).joined() + "</g>"
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(canvas)\" height=\"\(canvas)\" viewBox=\"0 0 512 512\"><title>Pulse</title>\(content)</svg>"
    try Data(svg.utf8).write(to: URL(fileURLWithPath: path))
}
func writePNG(_ path: String, size: Int, variant: Variant) throws {
    let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: image)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.clear(CGRect(x: 0, y: 0, width: size, height: size)); context.setShouldAntialias(true)
    context.translateBy(x: 0, y: CGFloat(size)); context.scaleBy(x: CGFloat(size) / 512, y: -CGFloat(size) / 512)
    let (base, inset, scale) = layout(variant); base.draw(context)
    context.translateBy(x: inset, y: inset); context.scaleBy(x: scale, y: scale)
    mark.forEach { $0.draw(context) }
    NSGraphicsContext.restoreGraphicsState()
    try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
try FileManager.default.createDirectory(atPath: "docs/icons", withIntermediateDirectories: true)
try writeSVG("docs/icons/pulse.svg", variant: .app)
try writeSVG("docs/icons/pulse-mac.svg", variant: .mac, canvas: 1024)
for size in [32, 180, 192, 512, 1024] { try writePNG("docs/icons/pulse-\(size).png", size: size, variant: .app) }
try writePNG("docs/icons/pulse-mac.png", size: 1024, variant: .mac)
try writePNG("desktop/windows/assets/icon.png", size: 512, variant: .windows)
print("Exported Pulse icons")

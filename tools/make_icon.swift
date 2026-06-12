// Renders the ShotQ app icon: a queue of screenshot cards with viewfinder
// brackets on an indigo gradient squircle.
// Usage: swift tools/make_icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not create bitmap rep") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background squircle (Apple icon grid: ~100px margin at 1024)
let inset: CGFloat = 100
let bgRect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.42, alpha: 1),
    NSColor(calibratedRed: 0.42, green: 0.23, blue: 0.69, alpha: 1),
])!.draw(in: bg, angle: 65)

// Queue: two ghost cards behind, solid card in front
let ghostSpecs: [(NSRect, CGFloat)] = [
    (NSRect(x: 232, y: 226, width: 430, height: 290), 0.30),
    (NSRect(x: 287, y: 287, width: 430, height: 290), 0.55),
]
for (rect, alpha) in ghostSpecs {
    NSColor.white.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 40, yRadius: 40).fill()
}

let front = NSRect(x: 342, y: 348, width: 430, height: 290)
NSColor.white.setFill()
NSBezierPath(roundedRect: front, xRadius: 40, yRadius: 40).fill()

// Viewfinder brackets on the front card
NSColor(calibratedRed: 0.38, green: 0.23, blue: 0.65, alpha: 1).setStroke()
let bracket = NSBezierPath()
bracket.lineWidth = 26
bracket.lineCapStyle = .round
bracket.lineJoinStyle = .round
let f = front.insetBy(dx: 52, dy: 52)
let len: CGFloat = 78
bracket.move(to: NSPoint(x: f.minX, y: f.minY + len))
bracket.line(to: NSPoint(x: f.minX, y: f.minY))
bracket.line(to: NSPoint(x: f.minX + len, y: f.minY))
bracket.move(to: NSPoint(x: f.maxX - len, y: f.minY))
bracket.line(to: NSPoint(x: f.maxX, y: f.minY))
bracket.line(to: NSPoint(x: f.maxX, y: f.minY + len))
bracket.move(to: NSPoint(x: f.minX, y: f.maxY - len))
bracket.line(to: NSPoint(x: f.minX, y: f.maxY))
bracket.line(to: NSPoint(x: f.minX + len, y: f.maxY))
bracket.move(to: NSPoint(x: f.maxX - len, y: f.maxY))
bracket.line(to: NSPoint(x: f.maxX, y: f.maxY))
bracket.line(to: NSPoint(x: f.maxX, y: f.maxY - len))
bracket.stroke()

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode failed") }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

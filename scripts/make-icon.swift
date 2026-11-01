// Renders Resources/AppIcon.icns (an original bell drawing — SF Symbols may not be used in app icons).
// Usage: swift scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024 // design on a 1024 grid

    // Background tile: Apple's icon grid puts the body at 824pt inset 100pt.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 20 * s
    shadow.set()
    NSColor.black.setFill(); tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(red: 0.96, green: 0.55, blue: 0.33, alpha: 1),
                        NSColor(red: 0.80, green: 0.33, blue: 0.20, alpha: 1)])!
        .draw(in: tilePath, angle: -90)

    // Bell
    let bell = NSBezierPath()
    bell.move(to: NSPoint(x: 262 * s, y: 372 * s))                       // bottom-left of lip
    bell.line(to: NSPoint(x: 762 * s, y: 372 * s))                       // lip
    bell.curve(to: NSPoint(x: 692 * s, y: 470 * s),
               controlPoint1: NSPoint(x: 762 * s, y: 420 * s), controlPoint2: NSPoint(x: 692 * s, y: 430 * s))
    bell.line(to: NSPoint(x: 692 * s, y: 580 * s))
    bell.curve(to: NSPoint(x: 512 * s, y: 760 * s),
               controlPoint1: NSPoint(x: 692 * s, y: 690 * s), controlPoint2: NSPoint(x: 612 * s, y: 760 * s))
    bell.curve(to: NSPoint(x: 332 * s, y: 580 * s),
               controlPoint1: NSPoint(x: 412 * s, y: 760 * s), controlPoint2: NSPoint(x: 332 * s, y: 690 * s))
    bell.line(to: NSPoint(x: 332 * s, y: 470 * s))
    bell.curve(to: NSPoint(x: 262 * s, y: 372 * s),
               controlPoint1: NSPoint(x: 332 * s, y: 430 * s), controlPoint2: NSPoint(x: 262 * s, y: 420 * s))
    bell.close()
    bell.append(NSBezierPath(ovalIn: NSRect(x: 477 * s, y: 742 * s, width: 70 * s, height: 70 * s)))  // knob
    bell.append(NSBezierPath(ovalIn: NSRect(x: 447 * s, y: 270 * s, width: 130 * s, height: 130 * s))) // clapper
    NSColor.white.setFill(); bell.fill()

    // Badge dot
    let badge = NSBezierPath(ovalIn: NSRect(x: 640 * s, y: 640 * s, width: 150 * s, height: 150 * s))
    NSColor(red: 0.92, green: 0.50, blue: 0.30, alpha: 1).setFill() // matches the tile gradient here
    NSBezierPath(ovalIn: NSRect(x: 620 * s, y: 620 * s, width: 190 * s, height: 190 * s)).fill()
    NSColor(red: 1.0, green: 0.86, blue: 0.45, alpha: 1).setFill(); badge.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! data.write(to: iconset.appendingPathComponent(name))
    }
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")

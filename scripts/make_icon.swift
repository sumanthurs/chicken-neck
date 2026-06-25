#!/usr/bin/env swift
// Renders the Chicken Neck app icon into Resources/AppIcon.icns.
// Run from the repo root:  swift scripts/make_icon.swift
import AppKit

func drawHead(in r: NSRect) {
    let s = min(r.width, r.height)
    let x = r.minX, y = r.minY
    func P(_ fx: CGFloat, _ fy: CGFloat) -> NSPoint { NSPoint(x: x + fx * s, y: y + fy * s) }
    let comb = NSColor(calibratedRed: 0.86, green: 0.22, blue: 0.20, alpha: 1)
    let beak = NSColor(calibratedRed: 0.96, green: 0.58, blue: 0.10, alpha: 1)
    let body = NSColor(calibratedRed: 0.98, green: 0.83, blue: 0.30, alpha: 1)

    let combPath = NSBezierPath()
    for cx: CGFloat in [0.30, 0.42, 0.54] {
        combPath.appendOval(in: NSRect(x: x + (cx - 0.06) * s, y: y + 0.66 * s, width: 0.12 * s, height: 0.16 * s))
    }
    comb.setFill(); combPath.fill()

    body.setFill()
    NSBezierPath(ovalIn: NSRect(x: x + 0.18 * s, y: y + 0.24 * s, width: 0.50 * s, height: 0.50 * s)).fill()

    let beakPath = NSBezierPath()
    beakPath.move(to: P(0.62, 0.52)); beakPath.line(to: P(0.86, 0.46)); beakPath.line(to: P(0.62, 0.40)); beakPath.close()
    beak.setFill(); beakPath.fill()

    comb.setFill()
    NSBezierPath(ovalIn: NSRect(x: x + 0.56 * s, y: y + 0.22 * s, width: 0.10 * s, height: 0.16 * s)).fill()

    NSColor.black.setFill()
    NSBezierPath(ovalIn: NSRect(x: x + 0.48 * s, y: y + 0.52 * s, width: 0.07 * s, height: 0.07 * s)).fill()
}

func icon(_ px: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: px, height: px), flipped: false) { rect in
        let bg = NSBezierPath(roundedRect: rect.insetBy(dx: px * 0.04, dy: px * 0.04),
                              xRadius: px * 0.22, yRadius: px * 0.22)
        NSColor(calibratedRed: 0.99, green: 0.93, blue: 0.74, alpha: 1).setFill(); bg.fill()
        drawHead(in: rect.insetBy(dx: px * 0.16, dy: px * 0.16))
        return true
    }
}

func png(_ image: NSImage, _ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = "Resources/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let specs: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"),
    (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x")
]
for (px, name) in specs {
    let data = png(icon(CGFloat(px)), px)
    try! data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
try? fm.removeItem(atPath: iconset)
print(p.terminationStatus == 0 ? "✓ Wrote Resources/AppIcon.icns" : "✗ iconutil failed")

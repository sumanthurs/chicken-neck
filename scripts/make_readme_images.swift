#!/usr/bin/env swift
// Generates representative chart images for the README into docs/.
//   swift scripts/make_readme_images.swift
import AppKit

let docs = "docs"
try? FileManager.default.createDirectory(atPath: docs, withIntermediateDirectories: true)

func write(_ image: NSImage, _ name: String, _ px: Int) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px * 1 / 2,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px / 2))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(docs)/\(name)"))
    print("wrote \(docs)/\(name)")
}

let W = 900.0, H = 450.0
let bg = NSColor(white: 0.11, alpha: 1)
let green = NSColor.systemGreen, orange = NSColor.systemOrange, red = NSColor.systemRed

// ---- Live neck-load line chart ----
let live = NSImage(size: NSSize(width: W, height: H), flipped: false) { _ in
    bg.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()
    let pad = 50.0
    let plotW = W - pad * 2, plotH = H - pad * 2
    let yMax = 30.0
    func y(_ v: Double) -> Double { pad + (v / yMax) * plotH }
    func x(_ i: Int, _ n: Int) -> Double { pad + Double(i) / Double(n - 1) * plotW }

    // threshold lines
    func dashed(_ v: Double, _ c: NSColor) {
        let p = NSBezierPath(); p.move(to: NSPoint(x: pad, y: y(v))); p.line(to: NSPoint(x: pad + plotW, y: y(v)))
        p.setLineDash([6, 4], count: 2, phase: 0); p.lineWidth = 1.5
        c.withAlphaComponent(0.6).setStroke(); p.stroke()
    }
    dashed(6, orange); dashed(12, red)

    // sample data: calm, then a forward-head spike into red, recover
    let data = [1.0,1,2,1,3,2,2,1,4,3,2,5,7,9,12,15,18,16,14,10,7,5,8,11,13,10,6,4,3,2,2,1,2,3,2,1]
    let n = data.count
    for i in 0..<(n - 1) {
        let v1 = data[i], v2 = data[i + 1]
        let seg = NSBezierPath()
        seg.move(to: NSPoint(x: x(i, n), y: y(v1)))
        seg.line(to: NSPoint(x: x(i + 1, n), y: y(v2)))
        seg.lineWidth = 3; seg.lineCapStyle = .round
        let hi = max(v1, v2)
        (hi >= 12 ? red : hi >= 6 ? orange : green).setStroke()
        seg.stroke()
    }
    // labels
    let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor(white: 0.7, alpha: 1),
                                                .font: NSFont.systemFont(ofSize: 18, weight: .medium)]
    ("Forward-head load (green → orange → red)" as NSString).draw(at: NSPoint(x: pad, y: H - 34), withAttributes: attrs)
    ("red line = sit-up-straight alert" as NSString).draw(at: NSPoint(x: pad, y: y(12) + 4),
        withAttributes: [.foregroundColor: red.withAlphaComponent(0.8), .font: NSFont.systemFont(ofSize: 13)])
    return true
}
write(live, "live-chart.png", Int(W))

// ---- Weekly history bar chart ----
let week = NSImage(size: NSSize(width: W, height: H), flipped: false) { _ in
    bg.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()
    let pad = 50.0
    let plotW = W - pad * 2, plotH = H - pad * 2
    let days = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
    let good = [220.0,260,180,300,240,90,60]
    let bad  = [60.0,40,90,30,70,20,15]
    let maxV = 360.0
    let slot = plotW / Double(days.count)
    let bw = slot * 0.5
    for i in 0..<days.count {
        let cx = pad + slot * Double(i) + slot / 2
        let gh = good[i] / maxV * plotH
        let bh = bad[i] / maxV * plotH
        green.setFill()
        NSBezierPath(roundedRect: NSRect(x: cx - bw/2, y: pad, width: bw, height: gh), xRadius: 3, yRadius: 3).fill()
        red.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: NSRect(x: cx - bw/2, y: pad + gh, width: bw, height: bh), xRadius: 3, yRadius: 3).fill()
        (days[i] as NSString).draw(at: NSPoint(x: cx - 16, y: 22),
            withAttributes: [.foregroundColor: NSColor(white: 0.7, alpha: 1), .font: NSFont.systemFont(ofSize: 16)])
    }
    let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor(white: 0.7, alpha: 1),
                                                .font: NSFont.systemFont(ofSize: 18, weight: .medium)]
    ("Weekly history, good (green) vs slouch (red), minutes" as NSString).draw(at: NSPoint(x: pad, y: H - 34), withAttributes: attrs)
    return true
}
write(week, "weekly-chart.png", Int(W))

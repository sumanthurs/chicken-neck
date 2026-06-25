import AppKit

/// Draws the Chicken Neck mascot — a little chicken head — entirely in code so
/// the app ships no image assets. Used both for the live menu-bar status icon
/// (tinted green/orange/red to signal posture) and the app icon.
enum ChickenIcon {

    /// Constant monochrome chicken for the menu bar — a template image so macOS
    /// tints it to match the bar (like the other status icons). MUST be a stable
    /// instance and the label MUST NOT read observable state, or SwiftUI's menu
    /// rebuild loops forever when a Window scene is also present.
    static let menuBarTemplate: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            drawHead(in: rect, fill: .black, detailed: false)
            return true
        }
        img.isTemplate = true
        return img
    }()

    /// Cache so the same colour returns the *same* NSImage instance — otherwise
    /// SwiftUI sees a "new" menu-bar label every render pass and loops forever.
    private static var menuBarCache: [String: NSImage] = [:]

    /// A small chicken-head silhouette filled with `color`, sized for the menu
    /// bar. Not a template image, so the posture colour shows through.
    static func menuBar(color: NSColor, size: CGFloat = 18) -> NSImage {
        let key = "\(color.description)#\(size)"
        if let cached = menuBarCache[key] { return cached }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawHead(in: rect, fill: color, detailed: false)
            return true
        }
        image.isTemplate = false
        menuBarCache[key] = image
        return image
    }

    /// A colourful, rounded app-icon rendering at the requested pixel size.
    static func appIcon(size: CGFloat) -> NSImage {
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // Soft rounded-square background (macOS app-icon shape).
            let bg = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.04, dy: size * 0.04),
                                  xRadius: size * 0.22, yRadius: size * 0.22)
            NSColor(calibratedRed: 0.99, green: 0.93, blue: 0.74, alpha: 1).setFill()
            bg.fill()
            let inner = rect.insetBy(dx: size * 0.16, dy: size * 0.16)
            drawHead(in: inner, fill: NSColor(calibratedRed: 0.98, green: 0.83, blue: 0.30, alpha: 1), detailed: true)
            return true
        }
    }

    /// Core silhouette: head, comb, beak, wattle (and eye when `detailed`).
    private static func drawHead(in r: NSRect, fill: NSColor, detailed: Bool) {
        let s = min(r.width, r.height)
        let x = r.minX, y = r.minY

        func P(_ fx: CGFloat, _ fy: CGFloat) -> NSPoint { NSPoint(x: x + fx * s, y: y + fy * s) }

        let combColor = NSColor(calibratedRed: 0.86, green: 0.22, blue: 0.20, alpha: 1)
        let beakColor = NSColor(calibratedRed: 0.96, green: 0.58, blue: 0.10, alpha: 1)

        // Comb (3 bumps on top of the head).
        let comb = NSBezierPath()
        for cx: CGFloat in [0.30, 0.42, 0.54] {
            comb.appendOval(in: NSRect(x: x + (cx - 0.06) * s, y: y + 0.66 * s,
                                       width: 0.12 * s, height: 0.16 * s))
        }
        (detailed ? combColor : fill).setFill()
        comb.fill()

        // Head.
        let head = NSBezierPath(ovalIn: NSRect(x: x + 0.18 * s, y: y + 0.24 * s,
                                               width: 0.50 * s, height: 0.50 * s))
        fill.setFill()
        head.fill()

        // Beak (triangle pointing right).
        let beak = NSBezierPath()
        beak.move(to: P(0.62, 0.52))
        beak.line(to: P(0.86, 0.46))
        beak.line(to: P(0.62, 0.40))
        beak.close()
        (detailed ? beakColor : fill).setFill()
        beak.fill()

        // Wattle (drop under the beak).
        let wattle = NSBezierPath(ovalIn: NSRect(x: x + 0.56 * s, y: y + 0.22 * s,
                                                 width: 0.10 * s, height: 0.16 * s))
        (detailed ? combColor : fill).setFill()
        wattle.fill()

        if detailed {
            // Eye.
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: x + 0.48 * s, y: y + 0.52 * s,
                                        width: 0.07 * s, height: 0.07 * s)).fill()
        }
    }
}

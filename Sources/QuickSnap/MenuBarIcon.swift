import AppKit

/// Drawn specifically at menu-bar size, with transparent corners around a white pill.
enum MenuBarIcon {
    static let size = NSSize(width: 22, height: 16)

    static func make() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 1, width: 22, height: 14),
                         xRadius: 4, yRadius: 4).fill()
            NSColor.black.setStroke()
            // The picture is an open corner, so the scissor blades remain distinct.
            let picture = NSBezierPath()
            picture.move(to: NSPoint(x: 11, y: 10.4))
            picture.line(to: NSPoint(x: 11, y: 12))
            picture.line(to: NSPoint(x: 18.3, y: 12))
            picture.line(to: NSPoint(x: 18.3, y: 5.5))
            picture.line(to: NSPoint(x: 16.2, y: 5.5))
            picture.lineWidth = 1.35; picture.lineJoinStyle = .round; picture.lineCapStyle = .round
            picture.stroke()
            for y in [3.3, 8.7] {
                let loop = NSBezierPath(ovalIn: NSRect(x: 3.3, y: y, width: 4, height: 3.4))
                loop.lineWidth = 1.5; loop.stroke()
            }
            for (start, end) in [(NSPoint(x: 7, y: 5), NSPoint(x: 15.3, y: 11)),
                                 (NSPoint(x: 7, y: 10.4), NSPoint(x: 15.3, y: 4.5))] {
                let blade = NSBezierPath(); blade.move(to: start); blade.line(to: end)
                blade.lineWidth = 1.5; blade.lineCapStyle = .round; blade.stroke()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Quick Snap"
        return image
    }
}

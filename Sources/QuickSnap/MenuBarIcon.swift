import AppKit

/// A white menu-bar badge with our simplified scissors-and-photo mark cut out of its alpha.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static func make() -> NSImage {
        let image = NSImage(size: size)
        for scale in [1, 2, 4] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.size = size
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 16, height: 16),
                         xRadius: 4, yRadius: 4).fill()
            context.cgContext.setBlendMode(.clear)
            drawMark()
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
        }
        image.isTemplate = false
        image.accessibilityDescription = "Quick Snap"
        return image
    }

    private static func stroke(_ path: NSBezierPath, width: CGFloat) {
        NSColor.black.setStroke() // The clear blend mode erases alpha instead of painting black.
        path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        path.stroke()
    }

    private static func drawMark() {
        // A near-square photo and diagonally overlapping scissors make a compact mark.
        let photo = NSBezierPath()
        photo.move(to: NSPoint(x: 7.6, y: 9))
        photo.line(to: NSPoint(x: 7.6, y: 13.3))
        photo.curve(to: NSPoint(x: 8.5, y: 14.2), controlPoint1: NSPoint(x: 7.6, y: 13.9), controlPoint2: NSPoint(x: 7.9, y: 14.2))
        photo.line(to: NSPoint(x: 14.4, y: 14.2))
        photo.curve(to: NSPoint(x: 15.3, y: 13.3), controlPoint1: NSPoint(x: 15, y: 14.2), controlPoint2: NSPoint(x: 15.3, y: 13.9))
        photo.line(to: NSPoint(x: 15.3, y: 7.1))
        photo.curve(to: NSPoint(x: 14.4, y: 6.2), controlPoint1: NSPoint(x: 15.3, y: 6.5), controlPoint2: NSPoint(x: 15, y: 6.2))
        photo.line(to: NSPoint(x: 12.4, y: 6.2))
        let mountain = NSBezierPath()
        mountain.move(to: NSPoint(x: 9.1, y: 11.2))
        mountain.line(to: NSPoint(x: 10.8, y: 12.6))
        mountain.line(to: NSPoint(x: 13.4, y: 10.9))
        let tilt = NSAffineTransform()
        tilt.translateX(by: 11.45, yBy: 10.2); tilt.rotate(byDegrees: -10)
        tilt.translateX(by: -11.45, yBy: -10.2)
        photo.transform(using: tilt as AffineTransform); mountain.transform(using: tilt as AffineTransform)
        stroke(photo, width: 1.2); stroke(mountain, width: 1.05)
        for y in [3.0, 7.2] {
            stroke(NSBezierPath(ovalIn: NSRect(x: 2.6, y: y, width: 3.7, height: 3.2)), width: 1.25)
        }
        for (start, end) in [(NSPoint(x: 6, y: 4.6), NSPoint(x: 12.3, y: 10)),
                             (NSPoint(x: 6, y: 8.8), NSPoint(x: 12.4, y: 4.6))] {
            let blade = NSBezierPath(); blade.move(to: start); blade.line(to: end)
            stroke(blade, width: 1.3)
        }
    }
}

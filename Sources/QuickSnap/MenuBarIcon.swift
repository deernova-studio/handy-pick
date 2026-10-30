import AppKit

/// A white menu-bar badge with our simplified scissors-and-photo mark cut out of its alpha.
enum MenuBarIcon {
    static let size = NSSize(width: 22, height: 16)

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
            NSBezierPath(roundedRect: NSRect(x: 0, y: 1, width: 22, height: 14),
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
        // Tilted photo card and a single mountain line, simplified from the application icon.
        let photo = NSBezierPath()
        photo.move(to: NSPoint(x: 10, y: 8.1))
        photo.line(to: NSPoint(x: 10, y: 11.9))
        photo.curve(to: NSPoint(x: 10.9, y: 12.8), controlPoint1: NSPoint(x: 10, y: 12.5), controlPoint2: NSPoint(x: 10.3, y: 12.8))
        photo.line(to: NSPoint(x: 17.5, y: 12.8))
        photo.curve(to: NSPoint(x: 18.4, y: 11.9), controlPoint1: NSPoint(x: 18.1, y: 12.8), controlPoint2: NSPoint(x: 18.4, y: 12.5))
        photo.line(to: NSPoint(x: 18.4, y: 6.9))
        photo.curve(to: NSPoint(x: 17.5, y: 6), controlPoint1: NSPoint(x: 18.4, y: 6.3), controlPoint2: NSPoint(x: 18.1, y: 6))
        photo.line(to: NSPoint(x: 15.4, y: 6))
        let mountain = NSBezierPath()
        mountain.move(to: NSPoint(x: 11.7, y: 10.1))
        mountain.line(to: NSPoint(x: 13.7, y: 11.5))
        mountain.line(to: NSPoint(x: 16.4, y: 9.7))
        let tilt = NSAffineTransform()
        tilt.translateX(by: 14.2, yBy: 9.4); tilt.rotate(byDegrees: -10)
        tilt.translateX(by: -14.2, yBy: -9.4)
        photo.transform(using: tilt as AffineTransform); mountain.transform(using: tilt as AffineTransform)
        stroke(photo, width: 1.2); stroke(mountain, width: 1.05)
        // The two loop handles and diagonal blades keep the brand's scissors silhouette.
        for y in [2.9, 7.1] {
            stroke(NSBezierPath(ovalIn: NSRect(x: 3, y: y, width: 3.9, height: 3.2)), width: 1.35)
        }
        for (start, end) in [(NSPoint(x: 6.7, y: 4.5), NSPoint(x: 14.3, y: 9.7)),
                             (NSPoint(x: 6.7, y: 8.7), NSPoint(x: 14.6, y: 4.4))] {
            let blade = NSBezierPath(); blade.move(to: start); blade.line(to: end)
            stroke(blade, width: 1.35)
        }
    }
}

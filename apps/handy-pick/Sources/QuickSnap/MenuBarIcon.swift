import AppKit

/// A template badge with our stacked-card mark cut out of its alpha.
/// AppKit chooses the foreground for the menu bar's actual appearance/highlight.
enum MenuBarIcon {
    static let size = NSSize(width: 22, height: 18)

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
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 20, height: 16),
                         xRadius: 4, yRadius: 4).fill()
            context.cgContext.setBlendMode(.clear)
            context.cgContext.translateBy(x: 11, y: 9)
            // Keep the badge unchanged; add breathing room only around its cutout.
            context.cgContext.scaleBy(x: 0.8, y: 0.8)
            context.cgContext.rotate(by: .pi / 15)
            context.cgContext.translateBy(x: -11, y: -9)
            drawMark()
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
        }
        image.isTemplate = true
        image.accessibilityDescription = "HandyPick"
        return image
    }

    private static func drawMark() {
        // Preserve the selected artwork's offset back card and lifted corner.
        // The wide gaps remain distinct at the 22 x 18 menu-bar size.
        let rear = NSBezierPath()
        rear.move(to: NSPoint(x: 5, y: 12))
        rear.line(to: NSPoint(x: 4.5, y: 12))
        rear.curve(to: NSPoint(x: 3, y: 10.5), controlPoint1: NSPoint(x: 3.5, y: 12), controlPoint2: NSPoint(x: 3, y: 11.5))
        rear.line(to: NSPoint(x: 3, y: 5))
        rear.curve(to: NSPoint(x: 4.5, y: 3.5), controlPoint1: NSPoint(x: 3, y: 4), controlPoint2: NSPoint(x: 3.5, y: 3.5))
        rear.line(to: NSPoint(x: 13, y: 3.5))
        rear.curve(to: NSPoint(x: 14.5, y: 5), controlPoint1: NSPoint(x: 14, y: 3.5), controlPoint2: NSPoint(x: 14.5, y: 4))
        rear.line(to: NSPoint(x: 7, y: 5))
        rear.curve(to: NSPoint(x: 5, y: 7), controlPoint1: NSPoint(x: 5.7, y: 5), controlPoint2: NSPoint(x: 5, y: 5.7))
        rear.close(); rear.fill()

        let card = NSBezierPath()
        card.move(to: NSPoint(x: 8, y: 14))
        card.line(to: NSPoint(x: 13.5, y: 14))
        card.line(to: NSPoint(x: 13.5, y: 11.5))
        card.curve(to: NSPoint(x: 15.5, y: 9.5), controlPoint1: NSPoint(x: 13.5, y: 10.2), controlPoint2: NSPoint(x: 14.2, y: 9.5))
        card.line(to: NSPoint(x: 18.5, y: 9.5))
        card.line(to: NSPoint(x: 18.5, y: 8))
        card.curve(to: NSPoint(x: 17, y: 6.5), controlPoint1: NSPoint(x: 18.5, y: 7), controlPoint2: NSPoint(x: 18, y: 6.5))
        card.line(to: NSPoint(x: 8, y: 6.5))
        card.curve(to: NSPoint(x: 6.5, y: 8), controlPoint1: NSPoint(x: 7, y: 6.5), controlPoint2: NSPoint(x: 6.5, y: 7))
        card.line(to: NSPoint(x: 6.5, y: 12.5))
        card.curve(to: NSPoint(x: 8, y: 14), controlPoint1: NSPoint(x: 6.5, y: 13.5), controlPoint2: NSPoint(x: 7, y: 14))
        card.close(); card.fill()

        let corner = NSBezierPath()
        corner.move(to: NSPoint(x: 15, y: 14))
        corner.line(to: NSPoint(x: 18.5, y: 11))
        corner.line(to: NSPoint(x: 16.5, y: 11))
        corner.curve(to: NSPoint(x: 15, y: 12.5), controlPoint1: NSPoint(x: 15.5, y: 11), controlPoint2: NSPoint(x: 15, y: 11.5))
        corner.close(); corner.fill()
    }
}

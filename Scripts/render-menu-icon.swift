import AppKit

@main struct RenderMenuIcon {
    static func save(_ path: String, size: NSSize, scale: Int, draw: () -> Void) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
            pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        draw()
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }

    static func main() throws {
        let icon = MenuBarIcon.make()
        try save("Resources/MenuIcon.png", size: MenuBarIcon.size, scale: 2) {
            icon.draw(in: NSRect(origin: .zero, size: MenuBarIcon.size))
        }
        try save("Resources/MenuIcon-preview.png", size: NSSize(width: 80, height: 24), scale: 4) {
            NSColor(calibratedRed: 0.24, green: 0.52, blue: 0.73, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 80, height: 24).fill()
            icon.draw(in: NSRect(x: 29, y: 3, width: 22, height: 18))
        }
    }
}

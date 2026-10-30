import AppKit

/// Standard monochrome menu-bar symbol; AppKit supplies the foreground color.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static func make(tint: NSColor? = nil) -> NSImage {
        let base = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Quick Snap")!
        var symbol = base.withSymbolConfiguration(.init(pointSize: 15, weight: .semibold)) ?? base
        if let tint { symbol = symbol.withSymbolConfiguration(.init(paletteColors: [tint])) ?? symbol }
        let factor = min(16 / symbol.size.width, 16 / symbol.size.height)
        let fitted = NSSize(width: symbol.size.width * factor, height: symbol.size.height * factor)
        let image = NSImage(size: size, flipped: false) { _ in
            symbol.draw(in: NSRect(x: (size.width-fitted.width)/2, y: (size.height-fitted.height)/2,
                                   width: fitted.width, height: fitted.height))
            return true
        }
        image.isTemplate = tint == nil
        image.accessibilityDescription = "Quick Snap"
        return image
    }
}

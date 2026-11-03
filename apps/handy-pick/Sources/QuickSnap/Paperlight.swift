import AppKit

/// Paperlight v2 semantic tokens from the supplied design system.
/// Keep appearance decisions here, independent of clipboard and capture behavior.
enum Paperlight {
    private static func color(_ name: String, _ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name("Paperlight.\(name)")) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255)/255,
                           green: CGFloat((value >> 8) & 255)/255, blue: CGFloat(value & 255)/255, alpha: 1)
        }
    }
    static let canvas = color("canvas", 0xf5f5f5, 0x161616)
    static let surface = color("surface", 0xfafafa, 0x1c1c1c)
    static let raised = color("surface-raised", 0xffffff, 0x252525)
    static let sunken = color("surface-sunken", 0xebebeb, 0x111111)
    static let ink = color("ink", 0x171717, 0xededed)
    static let secondary = color("ink-secondary", 0x525252, 0xa3a3a3)
    static let tertiary = color("ink-tertiary", 0x666666, 0x8c8c8c)
    static let line = color("line", 0xe3e3e3, 0x2f2f2f)
    static let controlLine = color("line-control", 0x8a8a8a, 0x737373)
    static let selected = color("accent-soft", 0xe8e8e8, 0x2e2e2e)
    static let onAccent = color("on-accent", 0xffffff, 0x161616)
    static let success = color("success", 0x1f6b66, 0x6cc3b4)
    static let body = NSFont.systemFont(ofSize: 13)
    static let label = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let caption = NSFont.systemFont(ofSize: 11)
    static func serif(_ size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }
    static func hairline(_ view: NSView) -> CGFloat { 1 / (view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2) }
}

class PaperlightSurface: NSView {
    var fill: NSColor = Paperlight.canvas
    var radius: CGFloat = 0
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        fill.setFill(); NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// Actual system glass on macOS 26, never CSS-style simulated glass.
/// Older supported Macs retain their native material; reduced transparency is opaque.
final class PaperlightGlass: NSView {
    let content = NSView()
    private var effect: NSView?
    private var accessibilityObserver: NSObjectProtocol?
    private let radius: CGFloat
    init(frame: NSRect, radius: CGFloat) {
        self.radius = radius; super.init(frame: frame)
        rebuild()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    private func rebuild() {
        content.removeFromSuperview(); effect?.removeFromSuperview()
        let background: NSView
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let paper = PaperlightSurface(frame: bounds); paper.fill = Paperlight.raised; paper.radius = radius
            paper.addSubview(content); background = paper
        } else if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .regular; glass.cornerRadius = radius; glass.contentView = content
            background = glass
        } else {
            let material = NSVisualEffectView(frame: bounds)
            material.material = .popover; material.blendingMode = .withinWindow; material.state = .active
            material.wantsLayer = true; material.layer?.cornerRadius = radius; material.layer?.masksToBounds = true
            material.addSubview(content); background = material
        }
        background.autoresizingMask = [.width, .height]
        content.frame = bounds; content.autoresizingMask = [.width, .height]
        addSubview(background); effect = background
    }
    deinit { if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) } }
}

class PaperlightButton: NSButton {
    enum Style { case plain, secondary, primary }
    var style: Style = .plain
    var cornerRadius: CGFloat = 6
    var isOnGlass = false
    var drawsTitleInsteadOfImage = false
    private(set) var hovered = false
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        focusRingType = .none
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: cornerRadius, yRadius: cornerRadius)
        if style == .primary { Paperlight.ink.setFill(); path.fill() }
        else if state == .on || isHighlighted || hovered { Paperlight.selected.setFill(); path.fill() }
        else if style == .secondary { Paperlight.raised.setFill(); path.fill() }
        if style == .secondary {
            (hovered ? Paperlight.controlLine : Paperlight.line).setStroke()
            path.lineWidth = Paperlight.hairline(self); path.stroke()
        }
        if window?.firstResponder === self {
            Paperlight.ink.setStroke(); path.lineWidth = 2; path.stroke()
        }
        let foreground = !isEnabled ? Paperlight.tertiary : (style == .primary ? Paperlight.onAccent : (state == .on || isOnGlass ? Paperlight.ink : Paperlight.secondary))
        if let image, !drawsTitleInsteadOfImage {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [foreground]))
            let symbol = image.withSymbolConfiguration(config) ?? image
            let size = symbol.size
            symbol.draw(in: NSRect(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2, width: size.width, height: size.height))
        } else {
            let attrs: [NSAttributedString.Key: Any] = [.font: font ?? Paperlight.label, .foregroundColor: foreground]
            let size = (title as NSString).size(withAttributes: attrs)
            (title as NSString).draw(at: NSPoint(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2), withAttributes: attrs)
        }
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }
}

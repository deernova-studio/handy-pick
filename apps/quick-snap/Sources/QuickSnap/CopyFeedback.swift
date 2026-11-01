import AppKit

/// A light, compact confirmation beside the pointer; never takes focus or intercepts clicks.
@MainActor final class CopyFeedback {
    private let panel: NSPanel
    private var dismissal: DispatchWorkItem?

    init() {
        panel = FeedbackPanel(contentRect: NSRect(x: 0, y: 0, width: 96, height: 32),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none

        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 96, height: 32))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        background.layer?.masksToBounds = true
        let symbol = NSImageView(frame: NSRect(x: 14, y: 10, width: 12, height: 12))
        symbol.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        symbol.contentTintColor = .systemGreen
        background.addSubview(symbol)
        let label = NSTextField(labelWithString: "已复制")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .left
        label.frame = NSRect(x: 34, y: 9, width: 48, height: 16)
        background.addSubview(label)
        panel.contentView = background
    }

    func show() {
        dismissal?.cancel()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return }
        let size = panel.frame.size
        // Offset from the pointer so the confirmation does not cover the selected text.
        let x = min(max(mouse.x + 16, bounds.minX + 6), bounds.maxX - size.width - 6)
        let y = min(max(mouse.y - size.height - 16, bounds.minY + 6), bounds.maxY - size.height - 6)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        panel.orderOut(nil)
    }
}

private final class FeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

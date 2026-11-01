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

        let background = PaperlightGlass(frame: NSRect(x: 0, y: 0, width: 96, height: 32), radius: 16)
        let symbol = NSImageView(frame: NSRect(x: 12, y: 9, width: 14, height: 14))
        symbol.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        symbol.contentTintColor = Paperlight.success
        background.content.addSubview(symbol)
        let label = NSTextField(labelWithString: "已复制")
        label.font = Paperlight.label
        label.textColor = Paperlight.ink
        label.alignment = .left
        label.frame = NSRect(x: 34, y: 9, width: 48, height: 16)
        background.content.addSubview(label)
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

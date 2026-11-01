import AppKit

/// Screen-level confirmation, centered near the top; never takes focus or intercepts clicks.
@MainActor final class CopyFeedback {
    private let panel: NSPanel
    private var dismissal: DispatchWorkItem?

    init() {
        panel = FeedbackPanel(contentRect: NSRect(x: 0, y: 0, width: 124, height: 40),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none

        let background = NSView(frame: NSRect(x: 0, y: 0, width: 124, height: 40))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(white: 0.10, alpha: 0.9).cgColor
        background.layer?.cornerRadius = 20
        background.layer?.masksToBounds = true
        let symbol = NSImageView(frame: NSRect(x: 23, y: 12, width: 16, height: 16))
        symbol.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        symbol.contentTintColor = .white
        background.addSubview(symbol)
        let label = NSTextField(labelWithString: "已复制")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .left
        label.frame = NSRect(x: 47, y: 12, width: 54, height: 17)
        background.addSubview(label)
        panel.contentView = background
    }

    func show() {
        dismissal?.cancel()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return }
        let size = panel.frame.size
        // Use the active display, but keep a stable position independent of the pointer.
        let x = bounds.midX - size.width / 2
        let y = bounds.maxY - size.height - 28
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

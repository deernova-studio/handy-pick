import AppKit

/// Brief confirmation beside the pointer; never takes focus or intercepts clicks.
@MainActor final class CopyFeedback {
    private let panel: NSPanel
    private var dismissal: DispatchWorkItem?

    init() {
        panel = FeedbackPanel(contentRect: NSRect(x: 0, y: 0, width: 112, height: 36),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none

        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 112, height: 36))
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        let label = NSTextField(labelWithString: "✓  已复制")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.frame = NSRect(x: 8, y: 10, width: 96, height: 17)
        background.addSubview(label)
        panel.contentView = background
    }

    func show() {
        dismissal?.cancel()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return }
        let size = panel.frame.size
        // Prefer below and to the right, and keep the entire badge on screen.
        let x = min(max(mouse.x + 14, bounds.minX + 6), bounds.maxX - size.width - 6)
        let y = min(max(mouse.y - size.height - 18, bounds.minY + 6), bounds.maxY - size.height - 6)
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

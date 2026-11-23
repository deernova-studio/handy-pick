import AppKit

/// Lets the user resolve an ambiguous gesture while keeping the original app active.
@MainActor final class EditChoicePanel: NSPanel {
    private var completion: CheckedContinuation<ShortcutAction?, Never>?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var buttons: [NSButton] = []
    private var keyboardChoice = 0

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        let bounds = NSRect(x: 0, y: 0, width: 168, height: 48)
        super.init(contentRect: bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.transient, .fullScreenAuxiliary, .moveToActiveSpace]
        title = "复制或粘贴"

        let surface = PaperlightSurface(frame: bounds)
        surface.radius = 12
        contentView = surface
        buttons = [ShortcutAction.copy, .paste].enumerated().map { index, action in
            let button = NSButton(title: action.title, target: self, action: #selector(selectAction(_:)))
            button.bezelStyle = .rounded
            button.tag = action.rawValue
            let rect = NSRect(x: 12 + CGFloat(index) * 76, y: 12, width: 68, height: 24)
            button.frame = button.frame(forAlignmentRect: rect)
            surface.addSubview(button)
            return button
        }
        initialFirstResponder = buttons[0]
    }

    func choose(at point: NSPoint) async -> ShortcutAction? {
        await withCheckedContinuation { continuation in
            completion = continuation
            let visible = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame
            var origin = NSPoint(x: point.x + 6, y: point.y - frame.height - 6)
            if let visible {
                origin.x = min(max(origin.x, visible.minX + 6), visible.maxX - frame.width - 6)
                if origin.y < visible.minY + 6 { origin.y = min(point.y + 6, visible.maxY - frame.height - 6) }
            }
            setFrameOrigin(origin)
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                if event.window === self {
                    if event.type == .keyDown, self.handleKey(event) { return nil }
                } else {
                    self.dismiss()
                }
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.dismiss()
            }
            makeKeyAndOrderFront(nil)
        }
    }

    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    func dismiss() { finish(with: nil) }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            dismiss()
        case 48, 123, 124:
            // Tab toggles; left and right select the corresponding button.
            keyboardChoice = event.keyCode == 48 ? 1 - keyboardChoice : (event.keyCode == 123 ? 0 : 1)
            makeFirstResponder(buttons[keyboardChoice])
        case 36, 49, 76:
            if !event.isARepeat { buttons[keyboardChoice].performClick(nil) }
        default:
            return false
        }
        return true
    }

    @objc private func selectAction(_ sender: NSButton) {
        finish(with: ShortcutAction(rawValue: sender.tag))
    }

    private func finish(with action: ShortcutAction?) {
        guard let completion else { return }
        self.completion = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        orderOut(nil)
        completion.resume(returning: action)
    }
}

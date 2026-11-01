import AppKit

/// A nonactivating panel keeps the current app as the shortcut's target.
final class ShortcutPanel: NSPanel {
    var onDismiss: (() -> Void)?
    var isRecording: (() -> Bool)?
    private var anchorRect = NSRect.zero
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(editor: NSViewController) {
        super.init(contentRect: NSRect(origin: .zero, size: editor.preferredContentSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        level = .popUpMenu; hidesOnDeactivate = false
        collectionBehavior = [.transient, .fullScreenAuxiliary, .moveToActiveSpace]
        animationBehavior = .utilityWindow
        title = "HandyPick"

        editor.loadViewIfNeeded()
        let background = PaperlightSurface(frame: NSRect(origin: .zero, size: editor.preferredContentSize))
        background.fill = Paperlight.canvas; background.radius = 12
        background.wantsLayer = true; background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        editor.view.frame = background.bounds
        editor.view.autoresizingMask = [.width, .height]
        background.addSubview(editor.view)
        contentView = background
        setContentSize(editor.preferredContentSize)
    }

    func show(below button: NSStatusBarButton) {
        guard let window = button.window else { return }
        anchorRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? anchorRect
        let x = min(max(anchorRect.midX - frame.width / 2, visible.minX + 6), visible.maxX - frame.width - 6)
        setFrameOrigin(NSPoint(x: x, y: anchorRect.minY - frame.height - 6))
        makeKeyAndOrderFront(nil)
        installDismissalMonitors()
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
        removeDismissalMonitors()
        onDismiss?()
    }

    private func installDismissalMonitors() {
        removeDismissalMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53, self.isRecording?() != true { self.dismiss(); return nil }
            } else { self.dismissIfOutside() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissIfOutside()
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.dismiss() }
    }

    private func dismissIfOutside() {
        let point = NSEvent.mouseLocation
        // Let the status button's own action toggle the panel, without reopening it.
        if !frame.contains(point), !anchorRect.contains(point) { dismiss() }
    }

    private func removeDismissalMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        localMonitor = nil; globalMonitor = nil; activationObserver = nil
    }

    deinit { removeDismissalMonitors() }
}

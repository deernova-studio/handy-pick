import AppKit
import ApplicationServices
import QuickSnapCore
import OSLog

final class MouseTrigger {
    var button: Int64 = 2
    var onAction: ((ClickRecognizer.Action) -> Void)?
    var onObservation: (() -> Void)?
    private(set) var pressCount = 0
    private(set) var lastButton: Int64?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let timer = ClickTimer()
    private var recognizer = ClickRecognizer(interval: NSEvent.doubleClickInterval)
    private var origin: CGPoint?
    private var frontmostPID: Int32 = 0
    private var activationObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "studio.deernova.quick-snap", category: "MouseTrigger")

    var running: Bool { tap != nil }
    var enabled: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() -> Bool {
        stop()
        guard AXIsProcessTrusted() else { return false }
        // Workspace queries may perform IPC. Keep them out of the synchronous event tap.
        frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            self?.frontmostPID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier ?? 0
        }
        let mask = (1 << CGEventType.otherMouseDown.rawValue) |
                   (1 << CGEventType.otherMouseUp.rawValue) |
                   (1 << CGEventType.otherMouseDragged.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<MouseTrigger>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                owner.logger.warning("Mouse event tap was disabled; re-enabled")
                return Unmanaged.passUnretained(event)
            }
            if type == .otherMouseDown {
                owner.pressCount += 1
                owner.lastButton = event.getIntegerValueField(.mouseEventButtonNumber)
                DispatchQueue.main.async { [weak owner] in owner?.onObservation?() }
            }
            guard event.getIntegerValueField(.mouseEventButtonNumber) == owner.button else {
                return Unmanaged.passUnretained(event)
            }
            if type == .otherMouseDown {
                owner.origin = event.location
                let target = owner.frontmostPID
                let actions = owner.recognizer.press(at: ProcessInfo.processInfo.systemUptime,
                                                     point: event.location, target: target)
                owner.handle(actions)
            } else if type == .otherMouseDragged, let origin = owner.origin,
                      hypot(event.location.x-origin.x, event.location.y-origin.y) > 6 {
                owner.timer.cancel(); owner.recognizer.cancel()
            } else if type == .otherMouseUp { owner.origin = nil }
            // Only the chosen auxiliary mouse button is consumed; scrolling and other buttons pass through.
            return nil
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { stop(); return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    private func handle(_ actions: [ClickRecognizer.Action]) {
        for action in actions {
            switch action {
            case .cancelSingle:
                timer.cancel()
            case .scheduleSingle(let deadline):
                timer.schedule(deadline: deadline) { [weak self] time in
                    guard let self, self.running,
                          let action = self.recognizer.singleDue(at: time) else { return }
                    self.logger.info("Single-click capture dispatched")
                    self.onAction?(action)
                }
            default:
                // Never run capture or paste work inside the event-tap callback.
                DispatchQueue.main.async { [weak self] in if self?.running == true { self?.onAction?(action) } }
            }
        }
    }

    func stop() {
        timer.cancel(); recognizer.cancel(); origin = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
    deinit { stop() }
}

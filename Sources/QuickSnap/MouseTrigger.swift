import AppKit
import ApplicationServices
import QuickSnapCore

final class MouseTrigger {
    var button: Int64 = 2
    var onAction: ((ClickRecognizer.Action) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pending: DispatchWorkItem?
    private var recognizer = ClickRecognizer(interval: NSEvent.doubleClickInterval)
    private var origin: CGPoint?

    var running: Bool { tap != nil }

    func start() -> Bool {
        stop()
        guard AXIsProcessTrusted() else { return false }
        let mask = (1 << CGEventType.otherMouseDown.rawValue) |
                   (1 << CGEventType.otherMouseUp.rawValue) |
                   (1 << CGEventType.otherMouseDragged.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<MouseTrigger>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard event.getIntegerValueField(.mouseEventButtonNumber) == owner.button else {
                return Unmanaged.passUnretained(event)
            }
            if type == .otherMouseDown {
                owner.origin = event.location
                let target = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
                let actions = owner.recognizer.press(at: ProcessInfo.processInfo.systemUptime,
                                                     point: event.location, target: target)
                owner.handle(actions)
            } else if type == .otherMouseDragged, let origin = owner.origin,
                      hypot(event.location.x-origin.x, event.location.y-origin.y) > 6 {
                owner.pending?.cancel(); owner.recognizer.cancel()
            } else if type == .otherMouseUp { owner.origin = nil }
            // Only the chosen auxiliary mouse button is consumed; scrolling and other buttons pass through.
            return nil
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
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
                pending?.cancel(); pending = nil
            case .scheduleSingle(let deadline):
                let item = DispatchWorkItem { [weak self] in
                    guard let self, self.running,
                          let action = self.recognizer.singleDue(at: ProcessInfo.processInfo.systemUptime) else { return }
                    self.onAction?(action)
                }
                pending = item
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline-ProcessInfo.processInfo.systemUptime), execute: item)
            default:
                // Never run capture or paste work inside the event-tap callback.
                DispatchQueue.main.async { [weak self] in if self?.running == true { self?.onAction?(action) } }
            }
        }
    }

    func stop() {
        pending?.cancel(); pending = nil; recognizer.cancel(); origin = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
    deinit { stop() }
}

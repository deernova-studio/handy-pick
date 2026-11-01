import AppKit
import ApplicationServices
import QuickSnapCore

/// Only key codes and modifier flags are inspected; typed text is never read or logged.
final class ShortcutTrigger {
    static let syntheticEventTag: Int64 = 0x51534E4150
    var binding: ShortcutBinding = .mouse(2)
    var onAction: ((ClickRecognizer.Gesture) -> Void)?
    var onRecorded: ((ShortcutBinding?) -> Void)?
    var suspended = false
    private(set) var recording = false
    private var active = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var localMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var frontmostPID: Int32 = 0
    private var recognizer = ClickRecognizer(interval: NSEvent.doubleClickInterval)
    private var origin: CGPoint?
    private var keyGate = KeyPressGate()
    private var heldModifiers: Set<UInt16> = []
    private var modifierCandidate: UInt16?
    private var generation = 0

    var running: Bool { active && tap != nil }

    @discardableResult func start(active: Bool) -> Bool {
        self.active = active
        guard active || recording else { stop(); return true }
        if tap != nil { return true }
        guard AXIsProcessTrusted() else { self.active = false; return false }
        frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.frontmostPID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier ?? 0
        }
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged, .keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<ShortcutTrigger>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return owner.process(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { stop(); return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        // Covers events addressed directly to this app while the shortcut recorder is open.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.recording, let cg = event.cgEvent else { return event }
            return self.process(cg.type, cg) ? nil : event
        }
        return true
    }

    func beginRecording() -> Bool {
        recognizer.cancel(); modifierCandidate = nil; keyGate.reset(); heldModifiers.removeAll()
        recording = true
        guard start(active: active) else { recording = false; return false }
        return true
    }

    func cancelRecording() {
        recording = false; modifierCandidate = nil; recognizer.cancel()
        if !active { stop() }
    }

    private func record(_ value: ShortcutBinding?) {
        recording = false; modifierCandidate = nil; recognizer.cancel()
        DispatchQueue.main.async { [weak self] in self?.onRecorded?(value) }
    }

    private func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
        // Our own ⌘V must pass through even when ⌘V is the configured double-press shortcut.
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventTag { return false }
        let code = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue
        var modifierDown = false
        if type == .flagsChanged {
            if code == 57 { modifierDown = true } // Caps Lock generates one flag transition per press.
            else if heldModifiers.contains(code) { heldModifiers.remove(code) }
            else if Self.modifierFlag(code).map({ event.flags.contains($0) }) == true {
                heldModifiers.insert(code); modifierDown = true
            }
        }
        if recording {
            if type == .otherMouseDown {
                let value = ShortcutBinding.mouse(event.getIntegerValueField(.mouseEventButtonNumber))
                if value.isValid { record(value); return true }
            } else if type == .keyDown {
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }
                if code == 53 { record(nil); return true }
                let value = ShortcutBinding.key(code, flags & ShortcutBinding.modifierMask)
                if value.isValid { record(value); return true }
            } else if type == .flagsChanged, ShortcutBinding.isModifier(code) {
                if modifierDown { modifierCandidate = code; if code == 57 { record(.modifier(code)) } }
                else if modifierCandidate == code { record(.modifier(code)) }
                // Modifier state continues to flow to the OS so it can never become stuck.
            }
            return false
        }
        // Pair releases even while the screenshot overlay temporarily suspends shortcuts.
        if type == .keyUp { return keyGate.up(code: code) == .consume }
        if type == .keyDown, let held = keyGate.heldResult(code: code) { return held == .consume }
        guard active, !suspended else { return false }
        switch binding {
        case .mouse(let selected):
            guard [.otherMouseDown, .otherMouseUp, .otherMouseDragged].contains(type),
                  event.getIntegerValueField(.mouseEventButtonNumber) == selected else { return false }
            if type == .otherMouseDown { origin = event.location; press(at: event.location, keyboard: false) }
            else if type == .otherMouseDragged, let origin,
                    hypot(event.location.x-origin.x, event.location.y-origin.y) > 6 { recognizer.cancel() }
            else if type == .otherMouseUp { origin = nil }
            return true
        case .key:
            guard type == .keyDown, binding.matchesKey(code, flags: flags),
                  event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return false }
            let allowShortcut = !binding.needsTypingProtection || TypingFocus.allowsShortcut(for: frontmostPID)
            if !allowShortcut { recognizer.cancel() }
            let result = keyGate.down(binding: binding, code: code, flags: flags,
                                      repeating: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                                      allowShortcut: allowShortcut)
            if result == .press { press(at: .zero, keyboard: true) }
            return result != .pass
        case .modifier(let selected):
            if type == .flagsChanged, code == selected, modifierDown { press(at: .zero, keyboard: true) }
            return false
        }
    }

    private func press(at point: CGPoint, keyboard: Bool) {
        guard let gesture = recognizer.press(at: ProcessInfo.processInfo.systemUptime, point: point, target: frontmostPID) else { return }
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, !self.recording, !self.suspended, self.generation == token else { return }
            if keyboard, self.binding.needsTypingProtection, !TypingFocus.allowsShortcut(for: gesture.target) {
                self.recognizer.cancel(); return
            }
            let mouse = NSEvent.mouseLocation
            let location = keyboard ? CGPoint(x: mouse.x, y: (NSScreen.screens.first?.frame.maxY ?? 0)-mouse.y) : gesture.point
            self.onAction?(ClickRecognizer.Gesture(target: gesture.target, point: location))
        }
    }

    private static func modifierFlag(_ code: UInt16) -> CGEventFlags? {
        switch code {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        case 63: return .maskSecondaryFn
        default: return nil
        }
    }

    func stop() {
        generation &+= 1; active = false; recording = false; suspended = false
        recognizer.cancel(); keyGate.reset(); heldModifiers.removeAll(); origin = nil
        if let observer = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        activationObserver = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
    deinit { stop() }
}

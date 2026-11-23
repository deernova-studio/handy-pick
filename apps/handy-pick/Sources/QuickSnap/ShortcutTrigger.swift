import AppKit
import ApplicationServices
import QuickSnapCore

/// Only key codes and modifier flags are inspected; typed text is never read or logged.
final class ShortcutTrigger {
    enum Interruption {
        case input
        case applicationChange
    }
    static let syntheticEventTag: Int64 = 0x51534E4150
    var bindings: [ShortcutAction: ShortcutBinding] = [:]
    var mode: ShortcutMode = .doublePress
    var onAction: ((Set<ShortcutAction>, pid_t, CGPoint) -> Void)?
    var onInteractionWhileSuspended: ((Interruption) -> Void)?
    var onRecorded: ((ShortcutBinding?) -> Void)?
    var onRecordingHint: ((String) -> Void)?
    var suspended = false {
        didSet {
            if suspended { recognizer.cancel(); mouseOrigin = nil; modifierCandidate = nil }
        }
    }
    private(set) var recording = false
    private var active = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var localMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var frontmostPID: Int32 = 0
    private var recognizer = ShortcutRecognizer(interval: NSEvent.doubleClickInterval)
    private var gestureBinding: ShortcutBinding?
    private var mouseOrigin: (button: Int64, point: CGPoint)?
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
            guard let self else { return }
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier ?? 0
            if pid != self.frontmostPID {
                self.recognizer.cancel()
                if self.suspended { self.onInteractionWhileSuspended?(.applicationChange) }
            }
            self.frontmostPID = pid
        }
        let types: [CGEventType] = [
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .keyDown, .keyUp, .flagsChanged
        ]
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
        generation &+= 1
        recognizer.cancel(); mouseOrigin = nil
        modifierCandidate = nil; keyGate.reset(); heldModifiers.removeAll()
        recording = true
        guard start(active: active) else { recording = false; return false }
        return true
    }

    func cancelRecording() {
        generation &+= 1
        recording = false; modifierCandidate = nil; recognizer.cancel()
        if !active { stop() }
    }

    private func record(_ value: ShortcutBinding?) {
        recording = false; modifierCandidate = nil; recognizer.cancel()
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            self.onRecorded?(value)
        }
    }

    private func acceptRecordedBinding(_ value: ShortcutBinding) {
        if mode.accepts(value) {
            record(value)
            return
        }
        let hint = mode == .chord ? "请按修饰键 + 主键" : "请换一个按键"
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.recording, self.generation == token else { return }
            self.onRecordingHint?(hint)
        }
    }

    private func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
        // Generated copy and paste events must never trigger another HandyPick shortcut.
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventTag { return false }
        let code = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue
        let modifier = type == .flagsChanged ? completedModifierPress(code, flags: event.flags) : nil
        if [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) {
            modifierCandidate = nil
            if case .modifier = gestureBinding { recognizer.cancel() }
            if suspended, type != .keyDown || keyGate.heldResult(code: code) == nil {
                onInteractionWhileSuspended?(.input)
            }
        }
        if recording {
            if type == .otherMouseDown {
                let value = ShortcutBinding.mouse(event.getIntegerValueField(.mouseEventButtonNumber))
                acceptRecordedBinding(value)
                return true
            } else if type == .keyDown {
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }
                if code == 53 { record(nil); return true }
                let value = ShortcutBinding.key(code, flags & ShortcutBinding.modifierMask)
                acceptRecordedBinding(value)
                return true
            } else if let modifier, mode == .doublePress {
                acceptRecordedBinding(modifier)
                // Modifier state continues to flow to the OS so it can never become stuck.
            }
            return false
        }
        // Pair releases even while the screenshot overlay temporarily suspends shortcuts.
        if type == .keyUp { return keyGate.up(code: code) == .consume }
        if type == .keyDown, let held = keyGate.heldResult(code: code) { return held == .consume }
        guard active, !suspended else { return false }
        let pressedBinding: ShortcutBinding
        switch type {
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            pressedBinding = .mouse(event.getIntegerValueField(.mouseEventButtonNumber))
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return false }
            pressedBinding = .key(code, flags & ShortcutBinding.modifierMask)
        case .flagsChanged:
            guard let modifier else { return false }
            pressedBinding = modifier
        default:
            return false
        }
        let actions = Set(bindings.compactMap { $0.value == pressedBinding ? $0.key : nil })
        guard !actions.isEmpty,
              mode.accepts(pressedBinding) else { return false }
        switch pressedBinding {
        case .mouse(let selected):
            if type == .otherMouseDown {
                mouseOrigin = (selected, event.location)
                press(pressedBinding, actions: actions, at: event.location)
            } else if let origin = mouseOrigin, origin.button == selected {
                if type == .otherMouseUp {
                    mouseOrigin = nil
                } else if gestureBinding == pressedBinding,
                          hypot(event.location.x - origin.point.x, event.location.y - origin.point.y) > 6 {
                    recognizer.cancel()
                }
            }
            return true
        case .key:
            let allowShortcut = mode.allowsActivation(for: pressedBinding, focusAllowsShortcut: TypingFocus.allowsShortcut(for: frontmostPID))
            if !allowShortcut { recognizer.cancel() }
            let result = keyGate.down(binding: pressedBinding, code: code, flags: flags, repeating: false, allowShortcut: allowShortcut)
            if result == .press { press(pressedBinding, actions: actions, at: .zero) }
            return result != .pass
        case .modifier:
            press(pressedBinding, actions: actions, at: .zero)
            return false
        }
    }

    private func completedModifierPress(_ code: UInt16, flags: CGEventFlags) -> ShortcutBinding? {
        if code == 57 { return .modifier(code) } // Caps Lock emits one transition per press.
        if heldModifiers.remove(code) != nil {
            guard modifierCandidate == code else { return nil }
            modifierCandidate = nil
            return .modifier(code)
        }
        guard Self.modifierFlag(code).map({ flags.contains($0) }) == true else { return nil }
        heldModifiers.insert(code)
        // Count a modifier on release only when it was tapped by itself.
        if recording || (active && !suspended) {
            modifierCandidate = heldModifiers.count == 1 ? code : nil
        }
        return nil
    }

    private func press(_ pressedBinding: ShortcutBinding, actions: Set<ShortcutAction>, at point: CGPoint) {
        if gestureBinding != pressedBinding {
            recognizer.cancel()
            gestureBinding = pressedBinding
        }
        guard let gesture = recognizer.press(mode: mode, at: ProcessInfo.processInfo.systemUptime, point: point, target: frontmostPID) else { return }
        let pointer: CGPoint
        if case .mouse = pressedBinding { pointer = gesture.point }
        else { pointer = CGEvent(source: nil)?.location ?? gesture.point }
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, !self.recording, !self.suspended, self.generation == token else { return }
            guard self.mode.allowsActivation(for: pressedBinding,
                focusAllowsShortcut: TypingFocus.allowsShortcut(for: gesture.target)) else { return }
            self.onAction?(actions, gesture.target, pointer)
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
        recognizer.cancel(); gestureBinding = nil; mouseOrigin = nil
        keyGate.reset(); heldModifiers.removeAll(); modifierCandidate = nil
        if let observer = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        activationObserver = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
    deinit { stop() }
}

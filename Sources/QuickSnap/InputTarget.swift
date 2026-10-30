import AppKit
import ApplicationServices
import QuickSnapCore

struct InputTarget {
    let element: AXUIElement
    let pid: pid_t

    /// Hit-test the pointer location, never just the previously focused input.
    static func at(_ point: CGPoint) -> InputTarget? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.35
        var current = hit
        // Text inside a web editor may be a child of the editable control.
        for _ in 0..<6 {
            guard let element = current, ProcessInfo.processInfo.systemUptime < deadline else { break }
            AXUIElementSetMessagingTimeout(element, 0.1)
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            let secure = (attribute(element, kAXSubroleAttribute) as? String) == (kAXSecureTextFieldSubrole as String)
            if secure { return nil }
            var settable: DarwinBoolean = false
            _ = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
            if InputPolicy.canPaste(role: role, secure: secure,
                    enabled: attribute(element, kAXEnabledAttribute) as? Bool,
                    editable: attribute(element, kAXIsEditableAttribute) as? Bool,
                    valueSettable: settable.boolValue) {
                var pid: pid_t = 0
                guard AXUIElementGetPid(element, &pid) == .success,
                      pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { return nil }
                return InputTarget(element: element, pid: pid)
            }
            // An explicit non-editable text control must not inherit eligibility from a parent.
            if [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role) { return nil }
            guard let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            let next = unsafeBitCast(parent, to: AXUIElement.self)
            if CFEqual(next, element) { break }
            current = next
        }
        return nil
    }

    func focus() {
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    func isFocused() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let focused = Self.attribute(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        var current = unsafeBitCast(focused, to: AXUIElement.self)
        for _ in 0..<6 {
            if CFEqual(current, element) { return true }
            guard let parent = Self.attribute(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            let next = unsafeBitCast(parent, to: AXUIElement.self)
            if CFEqual(next, current) { return false }
            current = next
        }
        return false
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

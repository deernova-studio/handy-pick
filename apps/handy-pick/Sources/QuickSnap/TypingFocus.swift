import AppKit
import ApplicationServices
import QuickSnapCore

/// A short, fail-open focus query, only for a new press of the bound typing key.
/// Never reads a value, selection text, or the characters carried by the key event.
enum TypingFocus {
    static func allowsShortcut(for pid: pid_t) -> Bool {
        guard pid > 0, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        let allowed = focusedControlAllowsShortcut(for: pid)
        return allowed && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    /// Separate the AX reader from foreground routing so real control trees can be tested safely.
    static func focusedControlAllowsShortcut(for pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.04
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.008)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let focused = unsafeBitCast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(focused, 0.008)
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focused, &focusedPID) == .success, focusedPID == pid else { return false }
        var values: CFArray?
        let attributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXIsEditableAttribute] as CFArray
        guard AXUIElementCopyMultipleAttributeValues(focused, attributes, [], &values) == .success,
              let items = values as? [Any], items.count == 3 else { return false }
        let role = items[0] as? String
        guard items[1] as? String != kAXSecureTextFieldSubrole as String,
              ![kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role ?? ""),
              ProcessInfo.processInfo.systemUptime < deadline else { return false }
        func settable(_ name: String) -> Bool? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            var result = DarwinBoolean(false)
            let status = AXUIElementIsAttributeSettable(focused, name as CFString, &result)
            if status == .attributeUnsupported { return false }
            return status == .success ? result.boolValue : nil
        }
        let allowed = TypingPolicy.canUseTypingKey(role: role, editable: items[2] as? Bool,
            valueSettable: settable(kAXValueAttribute), selectionSettable: settable(kAXSelectedTextAttribute))
        return allowed && ProcessInfo.processInfo.systemUptime < deadline
    }
}

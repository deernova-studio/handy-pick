import AppKit
import ApplicationServices
import QuickSnapCore

@MainActor struct InputTarget {
    let element: AXUIElement
    let pid: pid_t

    static func resolve(at point: CGPoint, foregroundPID: pid_t) async -> InputTarget? {
        let enabledWebAccessibility = enableWebAccessibility(for: foregroundPID)
        // Chromium publishes its renderer accessibility tree asynchronously.
        if enabledWebAccessibility { try? await Task.sleep(for: .milliseconds(100)) }
        for attempt in 0..<(enabledWebAccessibility ? 4 : 1) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == foregroundPID else { return nil }
            if let target = at(point) { return target }
            if attempt < 3, enabledWebAccessibility { try? await Task.sleep(for: .milliseconds(80)) }
        }
        return nil
    }

    private static func enableWebAccessibility(for pid: pid_t) -> Bool {
        guard AXIsProcessTrusted(), pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
              let bundle = NSRunningApplication(processIdentifier: pid)?.bundleURL else { return false }
        // Electron documents this opt-in for third-party accessibility clients:
        // https://www.electronjs.org/docs/latest/tutorial/accessibility#macos
        let frameworks = bundle.appendingPathComponent("Contents/Frameworks")
        guard FileManager.default.fileExists(atPath: frameworks.appendingPathComponent("Electron Framework.framework").path) else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let name = "AXManualAccessibility"
        guard attribute(app, name) as? Bool != true else { return false }
        return AXUIElementSetAttributeValue(app, name as CFString, kCFBooleanTrue) == .success
    }

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
        for _ in 0..<12 {
            guard let element = current, ProcessInfo.processInfo.systemUptime < deadline else { break }
            AXUIElementSetMessagingTimeout(element, 0.1)
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            let secure = (attribute(element, kAXSubroleAttribute) as? String) == (kAXSecureTextFieldSubrole as String)
            if secure { return nil }
            let textRole = [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role)
            let editable = attribute(element, kAXIsEditableAttribute) as? Bool
            // Avoid slow editability queries on unrelated ancestors and static text children.
            let candidate = textRole || (role == kAXGroupRole as String && editable == true)
            if InputPolicy.canPaste(role: role, secure: secure,
                    enabled: attribute(element, kAXEnabledAttribute) as? Bool,
                    editable: editable,
                    valueSettable: candidate && isSettable(element, kAXValueAttribute),
                    selectedTextSettable: candidate && isSettable(element, kAXSelectedTextAttribute)) {
                var pid: pid_t = 0
                guard AXUIElementGetPid(element, &pid) == .success,
                      pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { return nil }
                return InputTarget(element: element, pid: pid)
            }
            // An explicit non-editable text control must not inherit eligibility from a parent.
            if textRole { return nil }
            guard let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            let next = unsafeBitCast(parent, to: AXUIElement.self)
            if CFEqual(next, element) { break }
            current = next
        }
        return nil
    }

    func focus() {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        }
        _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    func isFocused() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        if Self.attribute(element, kAXFocusedAttribute) as? Bool == true { return true }
        guard let focused = Self.attribute(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
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

    private static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var result: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &result) == .success && result.boolValue
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

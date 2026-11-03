import AppKit
import ApplicationServices
import QuickSnapCore

@MainActor struct InputTarget {
    enum Action {
        case copy(String)
        case paste(InputTarget)
        case capture
        case unavailable
    }
    let element: AXUIElement
    let pid: pid_t

    static func resolve(at point: CGPoint, foregroundPID: pid_t) async -> Action {
        let enabledWebAccessibility = enableWebAccessibility(for: foregroundPID)
        // Chromium publishes its renderer accessibility tree asynchronously.
        if enabledWebAccessibility { try? await Task.sleep(for: .milliseconds(100)) }
        for attempt in 0..<(enabledWebAccessibility ? 4 : 1) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == foregroundPID else { return .unavailable }
            if let text = selectedText(at: point, foregroundPID: foregroundPID) { return .copy(text) }
            if let target = at(point), target.pid == foregroundPID { return .paste(target) }
            if attempt < 3, enabledWebAccessibility { try? await Task.sleep(for: .milliseconds(80)) }
        }
        return .capture
    }

    /// Read only the explicit selection under the pointer. Never read a whole
    /// document or send a speculative Cmd-C (some editors copy a line without a selection).
    private static func selectedText(at point: CGPoint, foregroundPID: pid_t) -> String? {
        guard AXIsProcessTrusted(), foregroundPID > 0,
              foregroundPID != ProcessInfo.processInfo.processIdentifier else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        var hitPID: pid_t = 0
        guard AXUIElementGetPid(hit, &hitPID) == .success, hitPID == foregroundPID else { return nil }
        var current: AXUIElement? = hit
        let deadline = ProcessInfo.processInfo.systemUptime + 0.35
        for _ in 0..<12 {
            guard let element = current, ProcessInfo.processInfo.systemUptime < deadline else { break }
            AXUIElementSetMessagingTimeout(element, 0.1)
            let secure = attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole as String
            if secure { return nil }
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            // Stop before window/application containers, which can expose a stale
            // selection belonging to an unrelated editor elsewhere in the window.
            if [kAXWindowRole as String, kAXApplicationRole as String].contains(role) { break }
            if let text = attribute(element, kAXSelectedTextAttribute) as? String,
               InputPolicy.canCopySelection(text, secure: secure) { return text }
            if let value = attribute(element, kAXSelectedTextRangeAttribute),
               CFGetTypeID(value) == AXValueGetTypeID() {
                var range = CFRange()
                if AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range), range.length > 0 {
                    var selected: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(element,
                        kAXStringForRangeParameterizedAttribute as CFString, value, &selected) == .success,
                       let text = selected as? String, InputPolicy.canCopySelection(text, secure: secure) { return text }
                }
            }
            // Do not inherit a selection from a surrounding web page when the
            // gesture is inside a different text field with an empty selection.
            if [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role) { break }
            guard let parent = elementAttribute(element, kAXParentAttribute), !CFEqual(parent, element) else { break }
            current = parent
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
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        var hitPID: pid_t = 0
        guard AXUIElementGetPid(hit, &hitPID) == .success,
              hitPID > 0, hitPID != ProcessInfo.processInfo.processIdentifier else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.35
        var current: AXUIElement? = hit
        // Text inside a web editor may be a child of the editable control.
        for _ in 0..<12 {
            guard let element = current, ProcessInfo.processInfo.systemUptime < deadline else { break }
            AXUIElementSetMessagingTimeout(element, 0.1)
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            let secure = (attribute(element, kAXSubroleAttribute) as? String) == (kAXSecureTextFieldSubrole as String)
            // Secure fields reject content reads, not user-initiated paste.
            if secure { return target(for: element) }
            // Chromium advertises this only for editable nodes. A contenteditable host
            // need not support replacing its whole AXValue or AXSelectedText via AX.
            if let host = webEditableHost(of: element), let target = target(for: host, webHost: true), target.pid == hitPID {
                return target
            }
            let textRole = [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role)
            let editable = attribute(element, kAXIsEditableAttribute) as? Bool
            if textRole, editable == false || attribute(element, kAXEnabledAttribute) as? Bool == false { return nil }
            // Avoid slow editability queries on unrelated ancestors and static text children.
            let candidate = textRole || (role == kAXGroupRole as String && editable == true)
            if candidate, let target = target(for: element) { return target }
            // An explicit non-editable text control must not inherit eligibility from a parent.
            if textRole { break }
            guard let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            let next = unsafeBitCast(parent, to: AXUIElement.self)
            if CFEqual(next, element) { break }
            current = next
        }
        // Some web hit tests return a containing group instead of the editor. Use
        // the focused control only when the pointer is inside its own bounds and
        // the topmost hit still belongs to the same foreground application.
        guard let focused = elementAttribute(AXUIElementCreateApplication(hitPID), kAXFocusedUIElementAttribute) else { return nil }
        let webHost = webEditableHost(of: focused)
        let candidate = webHost ?? focused
        guard let target = target(for: candidate, webHost: webHost != nil),
              let bounds = bounds(of: candidate),
              InputPolicy.canUseFocusedInput(at: point, bounds: bounds, hitPID: hitPID,
                  focusedPID: target.pid, foregroundPID: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0) else { return nil }
        return target
    }

    private static func target(for element: AXUIElement, webHost: Bool = false) -> InputTarget? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let secure = attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole as String
        let editable = attribute(element, kAXIsEditableAttribute) as? Bool
        guard InputPolicy.canPaste(role: role, secure: secure,
                  enabled: attribute(element, kAXEnabledAttribute) as? Bool, editable: editable,
                  valueSettable: isSettable(element, kAXValueAttribute),
                  selectedTextSettable: isSettable(element, kAXSelectedTextAttribute), webEditableHost: webHost) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        return InputTarget(element: element, pid: pid)
    }

    private static func webEditableHost(of element: AXUIElement) -> AXUIElement? {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let names = names as? [String], names.contains("AXEditableAncestor") else { return nil }
        // Requiring the attribute to be advertised matters: Chromium's getter can
        // otherwise return a text-field ancestor even when the queried node is read-only.
        return elementAttribute(element, "AXEditableAncestor")
    }

    private static func bounds(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
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

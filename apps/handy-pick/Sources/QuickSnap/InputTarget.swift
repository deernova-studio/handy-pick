import AppKit
import ApplicationServices
import QuickSnapCore

struct InputTarget: @unchecked Sendable {
    enum Action {
        case copy(String)
        case copyFocused(InputTarget)
        case chooseCopyOrPaste(InputTarget)
        case paste(InputTarget)
        case capture
        case unknownSelection
        case unavailable
    }
    private enum Selection {
        case text(String)
        case unreadableRange(AXUIElement)
        case empty
        case unknown
    }
    let element: AXUIElement
    let pid: pid_t
    var isEmbeddedTerminal = false

    // Blocking AX calls stay on worker queues, including focus checks.
    // A shared absolute deadline covers all retries, not one budget per attribute.
    private static let queue = DispatchQueue(label: "handypick.accessibility", qos: .userInitiated)
    private static let requestKey = "handypick.ax.request"
    private final class Request: @unchecked Sendable {
        let deadline: TimeInterval
        private let lock = NSLock()
        private var cancelled = false
        init(deadline: TimeInterval) { self.deadline = deadline }
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        var remaining: TimeInterval {
            lock.lock(); defer { lock.unlock() }
            return cancelled ? 0 : deadline - ProcessInfo.processInfo.systemUptime
        }
    }
    private static func perform<T>(until deadline: TimeInterval, _ operation: @escaping () -> T) async -> T {
        let request = Request(deadline: deadline)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async {
                    Thread.current.threadDictionary[requestKey] = request
                    defer { Thread.current.threadDictionary.removeObject(forKey: requestKey) }
                    continuation.resume(returning: operation())
                }
            }
        } onCancel: { request.cancel() }
    }
    private static func prepare(_ element: AXUIElement) -> Bool {
        guard let request = Thread.current.threadDictionary[requestKey] as? Request else { return false }
        let remaining = request.remaining
        guard remaining > 0 else { return false }
        AXUIElementSetMessagingTimeout(element, Float(min(0.05, remaining)))
        return true
    }

    @MainActor static func resolve(at point: CGPoint, foregroundPID: pid_t, actions: Set<ShortcutAction>) async -> Action {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.9
        let enabled = await perform(until: deadline) { enableWebAccessibility(for: foregroundPID) }
        if enabled { try? await Task.sleep(for: .milliseconds(100)) }
        for attempt in 0..<4 {
            guard canResolve(for: foregroundPID, until: deadline) else { return .unavailable }
            let result = await perform(until: deadline) {
                action(at: point, pid: foregroundPID, allowed: actions, finalAttempt: attempt == 3)
            }
            guard canResolve(for: foregroundPID, until: deadline) else { return .unavailable }
            if let result { return result }
            if attempt < 3 { try? await Task.sleep(for: .milliseconds(60)) }
        }
        return .unavailable
    }

    @MainActor private static func canResolve(for pid: pid_t, until deadline: TimeInterval) -> Bool {
        !Task.isCancelled && ProcessInfo.processInfo.systemUptime < deadline
            && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    private static func action(at point: CGPoint, pid: pid_t, allowed: Set<ShortcutAction>,
                               finalAttempt: Bool) -> Action? {
        let system = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        guard prepare(system),
              AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        var hitPID: pid_t = 0
        guard AXUIElementGetPid(hit, &hitPID) == .success, hitPID > 0,
              hitPID != ProcessInfo.processInfo.processIdentifier else { return nil }
        // Copy and paste belong to the foreground app. Capture may also start over
        // another app or the desktop without activating it.
        if hitPID != pid { return allowed.contains(.capture) ? .capture : .unavailable }
        let canCopy = allowed.contains(.copy)
        let canPaste = allowed.contains(.paste)
        if canCopy, let copy = copyAction(for: selection(at: hit), pid: pid) { return copy }
        if let input = input(at: point, hit: hit, pid: pid) {
            if input.isEmbeddedTerminal, canCopy {
                // The helper textarea's selection does not describe the terminal's selection.
                return canPaste ? .chooseCopyOrPaste(input) : .copyFocused(input)
            }
            if canCopy && canPaste {
                // Hit-testing may return a containing group or a web child. Read
                // the actual paste target before deciding that it has no selection.
                let selection = selection(of: input.element)
                if let copy = copyAction(for: selection, pid: pid) { return copy }
                guard case .empty = selection else { return finalAttempt ? .unknownSelection : nil }
            }
            return canPaste ? .paste(input) : .unavailable
        }
        if finalAttempt, allowed.contains(.capture), canConfirmBackground(hit, at: point, pid: pid) {
            return .capture
        }
        return nil
    }

    private static func canConfirmBackground(_ hit: AXUIElement, at point: CGPoint, pid: pid_t) -> Bool {
        let role = attribute(hit, kAXRoleAttribute) as? String
        let background = role == kAXWindowRole as String
            ? isConfirmedWindowBackground(hit, at: point)
            : isConfirmedBackgroundElement(hit)
        guard background else { return false }
        let app = AXUIElementCreateApplication(pid)
        if let focused = elementAttribute(app, kAXFocusedUIElementAttribute),
           let rect = bounds(of: focused), rect.contains(point) {
            guard let role = attribute(focused, kAXRoleAttribute) as? String else { return false }
            // A focused window covers all its controls; it is not an editor.
            if !["AXWindow", "AXApplication"].contains(role),
               !isConfirmedBackgroundElement(focused) { return false }
        }
        return true
    }

    private static func isConfirmedWindowBackground(_ window: AXUIElement, at point: CGPoint) -> Bool {
        guard attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole as String,
              let frame = bounds(of: window), frame.contains(point),
              let close = elementAttribute(window, kAXCloseButtonAttribute),
              let chrome = bounds(of: close), frame.contains(chrome),
              let children = attribute(window, kAXChildrenAttribute) as? [AXUIElement] else { return false }
        var hasExposedContent = false
        for child in children {
            guard let rect = bounds(of: child), !rect.contains(point),
                  let role = attribute(child, kAXRoleAttribute) as? String else { return false }
            if !["AXToolbar", "AXUnknown", "AXWindow"].contains(role),
               rect.minY >= chrome.maxY, !rect.isEmpty, frame.intersects(rect) {
                hasExposedContent = true
            }
        }
        return (chrome.minY <= point.y && point.y < chrome.maxY) || hasExposedContent
    }

    private static func isConfirmedBackgroundElement(_ start: AXUIElement) -> Bool {
        var current = start
        var confirmedLeaf = false
        for _ in 0..<12 {
            guard let role = attribute(current, kAXRoleAttribute) as? String else { return false }
            if ["AXTextArea", "AXTextField", "AXComboBox", "AXUnknown"].contains(role) { return false }
            if ["AXWindow", "AXApplication"].contains(role) { return confirmedLeaf }
            let editable = attribute(current, kAXIsEditableAttribute) as? Bool
            if editable == true || webEditableHost(of: current) != nil { return false }
            if ["AXGroup", "AXWebArea", "AXScrollArea"].contains(role) {
                // Missing editability on these roles means unknown, not false.
                guard editable == false else { return false }
                confirmedLeaf = true
            } else if ["AXButton", "AXImage", "AXStaticText", "AXLink", "AXToolbar", "AXMenuBar", "AXMenuItem"].contains(role) {
                confirmedLeaf = true
            } else { return false }
            guard let parent = elementAttribute(current, kAXParentAttribute), !CFEqual(parent, current) else { return false }
            current = parent
        }
        return false
    }

    private static func copyAction(for selection: Selection, pid: pid_t) -> Action? {
        switch selection {
        case .text(let text):
            return .copy(text)
        case .unreadableRange(let element):
            return .copyFocused(InputTarget(element: element, pid: pid))
        case .empty, .unknown:
            return nil
        }
    }

    private static func selection(at start: AXUIElement) -> Selection {
        var current: AXUIElement? = start
        let deadline = ProcessInfo.processInfo.systemUptime + 0.35
        for _ in 0..<12 {
            guard let element = current, ProcessInfo.processInfo.systemUptime < deadline else { break }
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            // Stop before window/application containers, which can expose a stale
            // selection belonging to an unrelated editor elsewhere in the window.
            if [kAXWindowRole as String, kAXApplicationRole as String].contains(role) { break }
            let result = selection(of: element)
            switch result {
            case .text, .unreadableRange: return result
            case .empty, .unknown: break
            }
            // Do not inherit a selection from a surrounding web page when the
            // gesture is inside a different text field with an empty selection.
            if [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role) { return result }
            guard let parent = elementAttribute(element, kAXParentAttribute), !CFEqual(parent, element) else { break }
            current = parent
        }
        return .unknown
    }

    /// A missing string is inconclusive. Check the range before allowing paste.
    private static func selection(of element: AXUIElement) -> Selection {
        guard attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole as String,
              !isTerminalHelper(element) else { return .unknown }
        let text = attribute(element, kAXSelectedTextAttribute) as? String
        if let text, !text.isEmpty { return .text(text) }

        var value: CFTypeRef?
        guard prepare(element) else { return .unknown }
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        if status == .attributeUnsupported || status == .noValue {
            return text == "" ? .empty : .unknown
        }
        guard status == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return .unknown }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range),
              range.location >= 0, range.location != NSNotFound, range.length >= 0 else { return .unknown }
        if range.length == 0 { return .empty }

        var selected: CFTypeRef?
        if prepare(element), AXUIElementCopyParameterizedAttributeValue(element,
            kAXStringForRangeParameterizedAttribute as CFString, value, &selected) == .success,
           let text = selected as? String, !text.isEmpty {
            return .text(text)
        }
        return .unreadableRange(element)
    }

    private static func enableWebAccessibility(for pid: pid_t) -> Bool {
        guard AXIsProcessTrusted(), pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
              let bundle = NSRunningApplication(processIdentifier: pid)?.bundleURL else { return false }
        // Electron documents this opt-in for third-party accessibility clients:
        // https://www.electronjs.org/docs/latest/tutorial/accessibility#macos
        let frameworks = bundle.appendingPathComponent("Contents/Frameworks")
        guard FileManager.default.fileExists(atPath: frameworks.appendingPathComponent("Electron Framework.framework").path) else { return false }
        let app = AXUIElementCreateApplication(pid)
        let name = "AXManualAccessibility"
        guard attribute(app, name) as? Bool != true else { return false }
        guard prepare(app) else { return false }
        return AXUIElementSetAttributeValue(app, name as CFString, kCFBooleanTrue) == .success
    }

    private static func input(at point: CGPoint, hit: AXUIElement, pid hitPID: pid_t) -> InputTarget? {
        if let terminal = focusedTerminal(at: point, hitPID: hitPID) { return terminal }
        if let terminal = focusedEmbeddedTerminal(at: point, hit: hit, hitPID: hitPID) { return terminal }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.35
        var current: AXUIElement? = hit
        // Text inside a web editor may be a child of the editable control.
        for _ in 0..<12 {
            guard let element = current, ProcessInfo.processInfo.systemUptime < deadline else { break }
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
            if candidate, let target = target(for: element), target.pid == hitPID { return target }
            // An explicit non-editable text control must not inherit eligibility from a parent.
            if textRole { break }
            guard let parent = elementAttribute(element, kAXParentAttribute), !CFEqual(parent, element) else { break }
            current = parent
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

    private static func focusedTerminal(at point: CGPoint, hitPID: pid_t) -> InputTarget? {
        let bundleID = NSRunningApplication(processIdentifier: hitPID)?.bundleIdentifier
        guard bundleID == "com.apple.Terminal" else { return nil }
        let app = AXUIElementCreateApplication(hitPID)
        guard let focused = elementAttribute(app, kAXFocusedUIElementAttribute) else { return nil }
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focused, &focusedPID) == .success,
              let rect = bounds(of: focused),
              InputPolicy.canPasteTerminal(bundleID: bundleID,
                role: attribute(focused, kAXRoleAttribute) as? String ?? "",
                secure: attribute(focused, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole as String,
                enabled: attribute(focused, kAXEnabledAttribute) as? Bool,
                point: point, bounds: rect, hitPID: hitPID, focusedPID: focusedPID,
                foregroundPID: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0) else { return nil }
        return InputTarget(element: focused, pid: focusedPID)
    }

    private static func focusedEmbeddedTerminal(at point: CGPoint, hit: AXUIElement, hitPID: pid_t) -> InputTarget? {
        let app = AXUIElementCreateApplication(hitPID)
        guard let focused = elementAttribute(app, kAXFocusedUIElementAttribute) else { return nil }
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focused, &focusedPID) == .success, focusedPID == hitPID else { return nil }
        guard isTerminalHelper(focused),
              let role = attribute(focused, kAXRoleAttribute) as? String,
              [kAXTextAreaRole as String, kAXTextFieldRole as String].contains(role),
              attribute(focused, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole as String,
              attribute(focused, kAXEnabledAttribute) as? Bool != false else { return nil }
        // The helper textarea only covers the cursor, so check its xterm surface.
        let focusAncestors = ancestors(of: focused)
        let hitAncestors = ancestors(of: hit)
        let hitIsContainer = ["AXGroup", "AXWebArea", "AXScrollArea"].contains(attribute(hit, kAXRoleAttribute) as? String ?? "")
        for surface in focusAncestors {
            let classes = attribute(surface, kAXDOMClassListAttribute as String) as? [String] ?? []
            guard InputPolicy.isEmbeddedTerminalSurface(classes: classes) else { continue }
            let hitInside = hitAncestors.contains(where: { CFEqual($0, surface) })
            let hitAbove = hitIsContainer && ancestors(of: surface).contains(where: { CFEqual($0, hit) })
            guard let rect = bounds(of: surface),
                  InputPolicy.canUseEmbeddedTerminalSurface(
                    hitInsideSurface: hitInside, hitIsAncestorContainer: hitAbove,
                    point: point, bounds: rect, hitPID: hitPID,
                    focusedPID: hitPID, foregroundPID: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0) else { continue }
            return InputTarget(element: focused, pid: hitPID, isEmbeddedTerminal: true)
        }
        return nil
    }

    private static func ancestors(of start: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = [], current: AXUIElement? = start
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        for _ in 0..<12 {
            guard let element = current, ProcessInfo.processInfo.systemUptime < deadline else { break }
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            if [kAXWindowRole as String, kAXApplicationRole as String].contains(role) { break }
            result.append(element)
            if role == "AXWebArea" { break }
            guard let parent = elementAttribute(element, kAXParentAttribute), !CFEqual(parent, element) else { break }
            current = parent
        }
        return result
    }

    private static func target(for element: AXUIElement, webHost: Bool = false) -> InputTarget? {
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let secure = attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole as String
        let editable = attribute(element, kAXIsEditableAttribute) as? Bool
        guard !isTerminalHelper(element),
              InputPolicy.canPaste(role: role, secure: secure,
                  enabled: attribute(element, kAXEnabledAttribute) as? Bool, editable: editable,
                  valueSettable: isSettable(element, kAXValueAttribute),
                  selectedTextSettable: isSettable(element, kAXSelectedTextAttribute), webEditableHost: webHost) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        return InputTarget(element: element, pid: pid)
    }

    private static func isTerminalHelper(_ element: AXUIElement) -> Bool {
        (attribute(element, kAXDOMClassListAttribute as String) as? [String])?.contains("xterm-helper-textarea") == true
    }

    private static func webEditableHost(of element: AXUIElement) -> AXUIElement? {
        var names: CFArray?
        guard prepare(element), AXUIElementCopyAttributeNames(element, &names) == .success,
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

    func focusForPaste() async -> Bool {
        if await isFocused() { return !Task.isCancelled }
        guard !Task.isCancelled else { return false }
        await Self.perform(until: ProcessInfo.processInfo.systemUptime + 0.25) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  Self.prepare(element) else { return }
            _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        for _ in 0..<10 {
            guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
            if await isFocused() { return !Task.isCancelled }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    func isFocused() async -> Bool {
        await Self.perform(until: ProcessInfo.processInfo.systemUptime + 0.2) { focusedOnWorker() }
    }

    private func focusedOnWorker() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        if Self.attribute(element, kAXFocusedAttribute) as? Bool == true { return true }
        guard var current = Self.elementAttribute(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute) else { return false }
        for _ in 0..<6 {
            if CFEqual(current, element) { return true }
            guard let parent = Self.elementAttribute(current, kAXParentAttribute), !CFEqual(parent, current) else { return false }
            current = parent
        }
        return false
    }

    private static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var result: DarwinBoolean = false
        return prepare(element) && AXUIElementIsAttributeSettable(element, name as CFString, &result) == .success && result.boolValue
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard prepare(element), AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

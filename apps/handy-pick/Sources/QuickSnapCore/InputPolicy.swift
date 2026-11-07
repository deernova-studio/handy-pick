import CoreGraphics

/// Only confirmed editable text controls are eligible for automatic paste.
public enum InputPolicy {
    public static func isEmbeddedTerminalInput(role: String, classes: [String], secure: Bool, enabled: Bool?) -> Bool {
        !secure && enabled != false && ["AXTextArea", "AXTextField"].contains(role)
            && classes.contains("xterm-helper-textarea")
    }

    public static func isEmbeddedTerminalSurface(classes: [String]) -> Bool {
        classes.contains("xterm") || classes.contains("xterm-screen")
    }

    public static func canUseEmbeddedTerminalSurface(hitInsideSurface: Bool, hitIsAncestorContainer: Bool,
                                                     point: CGPoint, bounds: CGRect, hitPID: Int32,
                                                     focusedPID: Int32, foregroundPID: Int32) -> Bool {
        // Chromium may hit-test canvas-rendered text to an enclosing container.
        // The hit relationship may widen, but the eligible rectangle never does.
        (hitInsideSurface || hitIsAncestorContainer) && canUseFocusedInput(at: point, bounds: bounds,
            hitPID: hitPID, focusedPID: focusedPID, foregroundPID: foregroundPID)
    }

    public static func canCopySelection(_ text: String?, secure: Bool) -> Bool {
        // Whitespace is valid selected content; an insertion cursor is not.
        !secure && !(text?.isEmpty ?? true)
    }
    public static func canPaste(role: String, secure: Bool, enabled: Bool?,
                                editable: Bool?, valueSettable: Bool,
                                selectedTextSettable: Bool = false,
                                webEditableHost: Bool = false) -> Bool {
        guard enabled != false, editable != false else { return false }
        // Password fields intentionally withhold AX value/selection setters.
        // A secure text-field role is sufficient for Cmd-V; never read its value.
        if secure { return role == "AXTextField" }
        if ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) {
            // Web editors can expose writable selected text without a writable whole value.
            return editable == true || valueSettable || selectedTextSettable || webEditableHost
        }
        // Some contenteditable hosts use a group role. Require explicit editability there.
        return role == "AXGroup" && (webEditableHost || (editable == true && (valueSettable || selectedTextSettable)))
    }

    /// Terminal displays a read-only screen buffer but accepts keyboard paste.
    /// Scope this exception to its focused terminal surface, never generic text areas.
    public static func canPasteTerminal(bundleID: String?, role: String, secure: Bool, enabled: Bool?,
                                        point: CGPoint, bounds: CGRect, hitPID: Int32,
                                        focusedPID: Int32, foregroundPID: Int32) -> Bool {
        guard bundleID == "com.apple.Terminal", role == "AXTextArea", !secure, enabled != false else { return false }
        return canUseFocusedInput(at: point, bounds: bounds, hitPID: hitPID,
                                  focusedPID: focusedPID, foregroundPID: foregroundPID)
    }

    public static func canUseFocusedInput(at point: CGPoint, bounds: CGRect,
                                          hitPID: Int32, focusedPID: Int32, foregroundPID: Int32) -> Bool {
        guard focusedPID > 0, hitPID == focusedPID, foregroundPID == focusedPID,
              point.x.isFinite, point.y.isFinite,
              bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else { return false }
        return bounds.contains(point)
    }
}

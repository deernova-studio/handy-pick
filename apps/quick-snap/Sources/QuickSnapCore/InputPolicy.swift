import CoreGraphics

/// Only confirmed editable text controls are eligible for automatic paste.
public enum InputPolicy {
    public static func canPaste(role: String, secure: Bool, enabled: Bool?,
                                editable: Bool?, valueSettable: Bool,
                                selectedTextSettable: Bool = false,
                                webEditableHost: Bool = false) -> Bool {
        guard !secure, enabled != false, editable != false else { return false }
        if ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) {
            // Web editors can expose writable selected text without a writable whole value.
            return editable == true || valueSettable || selectedTextSettable || webEditableHost
        }
        // Some contenteditable hosts use a group role. Require explicit editability there.
        return role == "AXGroup" && (webEditableHost || (editable == true && (valueSettable || selectedTextSettable)))
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

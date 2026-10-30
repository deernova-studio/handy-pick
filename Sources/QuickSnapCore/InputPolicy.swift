/// Only confirmed editable text controls are eligible for automatic paste.
public enum InputPolicy {
    public static func canPaste(role: String, secure: Bool, enabled: Bool?,
                                editable: Bool?, valueSettable: Bool) -> Bool {
        guard !secure, enabled != false, editable != false,
              ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) else { return false }
        return editable == true || valueSettable
    }
}

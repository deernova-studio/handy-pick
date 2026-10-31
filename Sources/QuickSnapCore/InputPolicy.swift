/// Only confirmed editable text controls are eligible for automatic paste.
public enum InputPolicy {
    public static func canPaste(role: String, secure: Bool, enabled: Bool?,
                                editable: Bool?, valueSettable: Bool,
                                selectedTextSettable: Bool = false) -> Bool {
        guard !secure, enabled != false, editable != false else { return false }
        if ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) {
            // Web editors can expose writable selected text without a writable whole value.
            return editable == true || valueSettable || selectedTextSettable
        }
        // Some contenteditable hosts use a group role. Require explicit editability there.
        return role == "AXGroup" && editable == true && (valueSettable || selectedTextSettable)
    }
}

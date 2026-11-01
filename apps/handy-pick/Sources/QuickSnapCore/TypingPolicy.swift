/// Unknown accessibility state must never turn a typing key into a swallowed shortcut.
public enum TypingPolicy {
    public static func canUseTypingKey(role: String?, editable: Bool?, valueSettable: Bool?, selectionSettable: Bool?) -> Bool {
        guard editable != true, valueSettable == false, selectionSettable == false, let role else { return false }
        // Standard non-editable containers include page backgrounds and window chrome.
        // A container with editable/value/selection support was rejected above.
        // Unknown custom roles and text controls still preserve normal input.
        return ["AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
                "AXSlider", "AXTabGroup", "AXOutline", "AXTable", "AXList", "AXMenuItem",
                "AXWebArea", "AXGroup", "AXScrollArea", "AXWindow"].contains(role)
    }
}

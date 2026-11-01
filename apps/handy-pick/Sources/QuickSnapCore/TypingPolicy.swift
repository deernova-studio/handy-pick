/// Unknown accessibility state must never turn a typing key into a swallowed shortcut.
public enum TypingPolicy {
    public static func canUseTypingKey(role: String?, editable: Bool?, valueSettable: Bool?, selectionSettable: Bool?) -> Bool {
        guard editable != true, valueSettable == false, selectionSettable == false, let role else { return false }
        // Text controls, web/group containers and custom editors intentionally fail open.
        return ["AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
                "AXSlider", "AXTabGroup", "AXOutline", "AXTable", "AXList", "AXMenuItem"].contains(role)
    }
}

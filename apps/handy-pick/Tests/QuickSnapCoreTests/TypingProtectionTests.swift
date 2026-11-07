import XCTest
@testable import QuickSnapCore

final class TypingProtectionTests: XCTestCase {
    func testTypingKeysAreProtectedWhileIntentionalChordsAndFunctionKeysRemainAvailable() {
        for code: UInt16 in [0, 18, 49, 51, 36, 48, 123, 126] {
            XCTAssertTrue(ShortcutBinding.key(code, 0).needsTypingProtection)
            XCTAssertFalse(ShortcutBinding.key(code, 1 << 17).needsTypingProtection)
        }
        for modifier: UInt64 in [1 << 17, 1 << 18, 1 << 19, 1 << 20] {
            XCTAssertFalse(ShortcutBinding.key(0, modifier).needsTypingProtection)
        }
        XCTAssertFalse(ShortcutBinding.key(122, 0).needsTypingProtection)
        XCTAssertFalse(ShortcutBinding.mouse(2).needsTypingProtection)
        XCTAssertFalse(ShortcutBinding.modifier(54).needsTypingProtection)
    }
    func testEditorsAndUnknownFocusAlwaysKeepNormalInput() {
        for role in [nil, "AXTextField", "AXTextArea", "AXComboBox", "CustomEditor"] {
            XCTAssertFalse(TypingPolicy.canUseTypingKey(role: role, editable: nil, valueSettable: false, selectionSettable: false))
        }
        XCTAssertFalse(TypingPolicy.canUseTypingKey(role: "AXButton", editable: true, valueSettable: false, selectionSettable: false))
        XCTAssertFalse(TypingPolicy.canUseTypingKey(role: "AXOutline", editable: nil, valueSettable: nil, selectionSettable: false))
        XCTAssertFalse(TypingPolicy.canUseTypingKey(role: "AXTable", editable: nil, valueSettable: false, selectionSettable: true))
        XCTAssertTrue(TypingPolicy.canUseTypingKey(role: "AXButton", editable: nil, valueSettable: false, selectionSettable: false))
        XCTAssertTrue(TypingPolicy.canUseTypingKey(role: "AXOutline", editable: false, valueSettable: false, selectionSettable: false))
    }
    func testNonEditablePageBackgroundsAllowShortcutsButEditableContainersDoNot() {
        for role in ["AXWebArea", "AXGroup", "AXScrollArea", "AXWindow"] {
            XCTAssertTrue(TypingPolicy.canUseTypingKey(role: role, editable: nil, valueSettable: false, selectionSettable: false))
            XCTAssertFalse(TypingPolicy.canUseTypingKey(role: role, editable: true, valueSettable: false, selectionSettable: false))
            XCTAssertFalse(TypingPolicy.canUseTypingKey(role: role, editable: nil, valueSettable: true, selectionSettable: false))
            XCTAssertFalse(TypingPolicy.canUseTypingKey(role: role, editable: nil, valueSettable: false, selectionSettable: true))
            XCTAssertFalse(TypingPolicy.canUseTypingKey(role: role, editable: nil, valueSettable: nil, selectionSettable: false))
        }
    }
    func testTypingKeyPassesDownRepeatAndUpEvenIfFocusChangesMidPress() {
        var gate = KeyPressGate()
        let key = ShortcutBinding.key(0, 0)
        XCTAssertEqual(gate.down(binding: key, code: 0, flags: 0, repeating: false, allowShortcut: false), .pass)
        XCTAssertEqual(gate.heldResult(code: 0), .pass)
        XCTAssertEqual(gate.down(binding: key, code: 0, flags: 0, repeating: true, allowShortcut: true), .pass)
        XCTAssertEqual(gate.up(code: 0), .pass)
        XCTAssertNil(gate.heldResult(code: 0))
        XCTAssertEqual(gate.down(binding: key, code: 0, flags: 0, repeating: false, allowShortcut: true), .press)
        XCTAssertEqual(gate.up(code: 0), .consume)
    }
    func testConsecutiveTypingPressesCannotCreateShortcutGesture() {
        var gate = KeyPressGate()
        var recognizer = ClickRecognizer(interval: 0.4)
        let key = ShortcutBinding.key(0, 0)
        for time in [1.0, 1.1] {
            let result = gate.down(binding: key, code: 0, flags: 0, repeating: false, allowShortcut: false)
            if result == .press { XCTFail("Typing reached the gesture recognizer at \(time)") }
            else { recognizer.cancel() }
            XCTAssertEqual(gate.up(code: 0), .pass)
        }
        XCTAssertNil(recognizer.press(at: 1.2, point: .zero, target: 1))
    }
    func testConsumedPressKeepsRepeatsAndReleasePairedAcrossModifierOrFocusChanges() {
        var gate = KeyPressGate()
        let key = ShortcutBinding.key(0, 1 << 20)
        XCTAssertEqual(gate.down(binding: key, code: 0, flags: 1 << 20, repeating: false), .press)
        XCTAssertEqual(gate.down(binding: key, code: 0, flags: 0, repeating: true, allowShortcut: false), .consume)
        XCTAssertEqual(gate.heldResult(code: 0), .consume)
        XCTAssertEqual(gate.up(code: 0), .consume)
    }
    func testAlreadyRepeatingKeyNeverStartsAShortcutWhenMonitoringBegins() {
        var gate = KeyPressGate()
        let key = ShortcutBinding.key(0, 0)
        XCTAssertEqual(gate.down(binding: key, code: 0, flags: 0, repeating: true), .pass)
        XCTAssertEqual(gate.up(code: 0), .pass)
    }
}

import XCTest
import CoreGraphics
@testable import QuickSnapCore

final class QuickSnapCoreTests: XCTestCase {
    func testTerminalPasteRequiresFocusedSurfaceUnderPointerInForeground() {
        let bounds = CGRect(x: 100, y: 100, width: 600, height: 400)
        func allowed(bundle: String? = "com.apple.Terminal", role: String = "AXTextArea",
                     secure: Bool = false, enabled: Bool? = nil, point: CGPoint = CGPoint(x: 200, y: 200),
                     hit: Int32 = 10, focused: Int32 = 10, foreground: Int32 = 10) -> Bool {
            InputPolicy.canPasteTerminal(bundleID: bundle, role: role, secure: secure, enabled: enabled,
                point: point, bounds: bounds, hitPID: hit, focusedPID: focused, foregroundPID: foreground)
        }
        XCTAssertTrue(allowed())
        XCTAssertFalse(allowed(bundle: "com.apple.TextEdit"))
        XCTAssertFalse(allowed(bundle: nil))
        for role in ["AXWindow", "AXGroup", "AXButton", "AXStaticText", "AXTextField"] {
            XCTAssertFalse(allowed(role: role))
        }
        XCTAssertFalse(allowed(secure: true)); XCTAssertFalse(allowed(enabled: false))
        XCTAssertFalse(allowed(point: CGPoint(x: 50, y: 200)))
        XCTAssertFalse(allowed(point: CGPoint(x: 200, y: 80)))
        XCTAssertFalse(allowed(hit: 11)); XCTAssertFalse(allowed(focused: 11)); XCTAssertFalse(allowed(foreground: 11))
        XCTAssertFalse(InputPolicy.canPaste(role: "AXTextArea", secure: false, enabled: true,
                                           editable: false, valueSettable: false))
    }
    func testSelectionCopyPreservesWhitespaceAndRejectsCursorOrSecureFields() {
        XCTAssertTrue(InputPolicy.canCopySelection("你好 👋\nSecond line", secure: false))
        XCTAssertTrue(InputPolicy.canCopySelection(" \t\n", secure: false))
        XCTAssertFalse(InputPolicy.canCopySelection("", secure: false))
        XCTAssertFalse(InputPolicy.canCopySelection(nil, secure: false))
        XCTAssertFalse(InputPolicy.canCopySelection("password", secure: true))
    }
    func testShortcutRoundTripPreservesPhysicalKeyAndModifiers() throws {
        for binding in [ShortcutBinding.mouse(2), .mouse(7), .key(40, 1 << 20), .modifier(54)] {
            let data = try JSONEncoder().encode(binding)
            XCTAssertEqual(try JSONDecoder().decode(ShortcutBinding.self, from: data), binding)
        }
    }
    func testRecorderRejectsPrimaryMouseButtonsAndEscape() {
        for binding in [ShortcutBinding.mouse(0), .mouse(1), .mouse(32), .key(53, 0), .key(55, 0), .modifier(40)] {
            XCTAssertFalse(binding.isValid)
        }
        XCTAssertTrue(ShortcutBinding.key(40, 1 << 20).isValid)
        XCTAssertTrue(ShortcutBinding.modifier(55).isValid)
    }
    func testKeyboardChordRequiresExactModifiersButIgnoresCapsLock() {
        let command: UInt64 = 1 << 20
        let binding = ShortcutBinding.key(40, command)
        XCTAssertTrue(binding.matchesKey(40, flags: command | (1 << 16)))
        XCTAssertFalse(binding.matchesKey(40, flags: 0))
        XCTAssertFalse(binding.matchesKey(40, flags: command | (1 << 17)))
        XCTAssertFalse(binding.matchesKey(41, flags: command))
    }
    func testHoldingKeyNeverBecomesDoublePress() {
        var gate = KeyPressGate()
        let binding = ShortcutBinding.key(40, 0)
        XCTAssertEqual(gate.down(binding: binding, code: 40, flags: 0, repeating: false), .press)
        XCTAssertEqual(gate.down(binding: binding, code: 40, flags: 0, repeating: true), .consume)
        XCTAssertEqual(gate.down(binding: binding, code: 40, flags: 0, repeating: false), .consume)
        XCTAssertEqual(gate.up(code: 40), .consume)
        XCTAssertEqual(gate.down(binding: binding, code: 40, flags: 0, repeating: false), .press)
    }
    func testOtherKeysPassAndSwallowedKeyUpIsPaired() {
        var gate = KeyPressGate()
        let binding = ShortcutBinding.key(40, 1 << 20)
        XCTAssertEqual(gate.down(binding: binding, code: 40, flags: 0, repeating: false), .pass)
        XCTAssertEqual(gate.down(binding: binding, code: 41, flags: 1 << 20, repeating: false), .pass)
        XCTAssertEqual(gate.down(binding: binding, code: 40, flags: 1 << 20, repeating: false), .press)
        XCTAssertEqual(gate.up(code: 41), .pass)
        XCTAssertEqual(gate.up(code: 40), .consume)
        XCTAssertEqual(gate.up(code: 40), .pass)
    }
    func testPauseClearsKeyboardHeldState() {
        var gate = KeyPressGate()
        let binding = ShortcutBinding.key(40, 0)
        _ = gate.down(binding: binding, code: 40, flags: 0, repeating: false)
        gate.reset()
        XCTAssertEqual(gate.up(code: 40), .pass)
        XCTAssertEqual(gate.down(binding: binding, code: 40, flags: 0, repeating: false), .press)
    }
    func testSingleClickNeverTriggersAnAction() {
        var gesture = ClickRecognizer(interval: 0.3)
        XCTAssertNil(gesture.press(at: 10, point: .zero, target: 42))
        // A click after the interval begins a new pair rather than performing the old single.
        XCTAssertNil(gesture.press(at: 11, point: .zero, target: 42))
    }
    func testDoubleClickReportsExactPointerLocationOnce() {
        var gesture = ClickRecognizer(interval: 0.4)
        XCTAssertNil(gesture.press(at: 10, point: CGPoint(x: 50, y: 80), target: 42))
        let result = gesture.press(at: 10.15, point: CGPoint(x: 52, y: 81), target: 42)
        XCTAssertEqual(result?.target, 42)
        XCTAssertEqual(result?.point, CGPoint(x: 52, y: 81))
        XCTAssertNil(gesture.press(at: 10.2, point: CGPoint(x: 52, y: 81), target: 42))
    }
    func testChangedAppCannotCompleteDoubleClick() {
        var gesture = ClickRecognizer(interval: 0.4)
        _ = gesture.press(at: 10, point: .zero, target: 42)
        XCTAssertNil(gesture.press(at: 10.1, point: .zero, target: 43))
        XCTAssertEqual(gesture.press(at: 10.2, point: .zero, target: 43)?.target, 43)
    }
    func testDistantClicksAreSeparateSingles() {
        var gesture = ClickRecognizer(interval: 0.4)
        _ = gesture.press(at: 10, point: .zero, target: 42)
        XCTAssertNil(gesture.press(at: 10.1, point: CGPoint(x: 100, y: 100), target: 42))
    }
    func testPauseOrDragCancelsDoubleClickPair() {
        var gesture = ClickRecognizer(interval: 0.4)
        _ = gesture.press(at: 10, point: .zero, target: 42)
        gesture.cancel()
        XCTAssertNil(gesture.press(at: 10.1, point: .zero, target: 42))
    }
    func testSlowOrOutOfOrderClicksDoNotTrigger() {
        var gesture = ClickRecognizer(interval: 0.3)
        _ = gesture.press(at: 2, point: .zero, target: 42)
        XCTAssertNil(gesture.press(at: 1, point: .zero, target: 42))
        XCTAssertNil(gesture.press(at: 3, point: .zero, target: 42))
    }
    func testFourClicksProduceTwoGestures() {
        var gesture = ClickRecognizer(interval: 0.4)
        let results = [10.0, 10.1, 10.2, 10.3].compactMap { gesture.press(at: $0, point: .zero, target: 42) }
        XCTAssertEqual(results.count, 2)
    }
    func testOnlyConfirmedEditableControlsCanReceivePaste() {
        for role in ["AXTextArea", "AXTextField", "AXComboBox"] {
            XCTAssertTrue(InputPolicy.canPaste(role: role, secure: false, enabled: true, editable: nil, valueSettable: true))
            XCTAssertTrue(InputPolicy.canPaste(role: role, secure: false, enabled: nil, editable: true, valueSettable: false))
        }
        XCTAssertFalse(InputPolicy.canPaste(role: "AXStaticText", secure: false, enabled: true, editable: nil, valueSettable: true))
        XCTAssertFalse(InputPolicy.canPaste(role: "AXTextArea", secure: false, enabled: true, editable: nil, valueSettable: false))
    }
    func testReadOnlyAndDisabledFieldsRejectPaste() {
        XCTAssertFalse(InputPolicy.canPaste(role: "AXTextArea", secure: false, enabled: true, editable: false, valueSettable: true))
        XCTAssertFalse(InputPolicy.canPaste(role: "AXTextField", secure: false, enabled: false, editable: true, valueSettable: true))
        XCTAssertFalse(InputPolicy.canPaste(role: "AXTextField", secure: true, enabled: false, editable: true, valueSettable: true))
    }
    func testWebEditorCanReplaceSelectionWithoutSettingWholeValue() {
        XCTAssertTrue(InputPolicy.canPaste(role: "AXTextArea", secure: false, enabled: true,
                        editable: nil, valueSettable: false, selectedTextSettable: true))
        XCTAssertFalse(InputPolicy.canPaste(role: "AXTextArea", secure: false, enabled: true,
                        editable: false, valueSettable: false, selectedTextSettable: true))
        XCTAssertFalse(InputPolicy.canPaste(role: "AXStaticText", secure: false, enabled: true,
                        editable: nil, valueSettable: false, selectedTextSettable: true))
    }
    func testGenericEditorHostNeedsExplicitEditingCapability() {
        XCTAssertTrue(InputPolicy.canPaste(role: "AXGroup", secure: false, enabled: true,
                        editable: true, valueSettable: false, selectedTextSettable: true))
        XCTAssertFalse(InputPolicy.canPaste(role: "AXGroup", secure: false, enabled: true,
                        editable: nil, valueSettable: false, selectedTextSettable: true))
        XCTAssertFalse(InputPolicy.canPaste(role: "AXGroup", secure: false, enabled: true,
                        editable: true, valueSettable: false))
        XCTAssertTrue(InputPolicy.canPaste(role: "AXTextField", secure: true, enabled: true,
                        editable: true, valueSettable: false, selectedTextSettable: true))
    }
    func testSecureTextFieldAcceptsPasteWithoutExposingItsContents() {
        XCTAssertTrue(InputPolicy.canPaste(role: "AXTextField", secure: true, enabled: true,
                         editable: nil, valueSettable: false, selectedTextSettable: false))
        XCTAssertFalse(InputPolicy.canCopySelection("fixture", secure: true))
        XCTAssertFalse(InputPolicy.canPaste(role: "AXTextField", secure: true, enabled: true,
                         editable: false, valueSettable: false))
        XCTAssertFalse(InputPolicy.canPaste(role: "AXGroup", secure: true, enabled: true,
                         editable: true, valueSettable: true))
    }
    func testAdvertisedWebEditableHostDoesNotNeedAXValueSetter() {
        for role in ["AXTextArea", "AXGroup"] {
            XCTAssertTrue(InputPolicy.canPaste(role: role, secure: false, enabled: true,
                            editable: nil, valueSettable: false, webEditableHost: true))
            XCTAssertFalse(InputPolicy.canPaste(role: role, secure: false, enabled: true,
                            editable: false, valueSettable: false, webEditableHost: true))
            XCTAssertFalse(InputPolicy.canPaste(role: role, secure: true, enabled: true,
                            editable: nil, valueSettable: false, webEditableHost: true))
            XCTAssertFalse(InputPolicy.canPaste(role: role, secure: false, enabled: false,
                            editable: nil, valueSettable: false, webEditableHost: true))
        }
        XCTAssertFalse(InputPolicy.canPaste(role: "AXButton", secure: false, enabled: true,
                        editable: nil, valueSettable: false, webEditableHost: true))
    }
    func testFocusedEditorFallbackRequiresPointerInsideSameForegroundApp() {
        let bounds = CGRect(x: 100, y: 200, width: 300, height: 100)
        XCTAssertTrue(InputPolicy.canUseFocusedInput(at: CGPoint(x: 200, y: 250), bounds: bounds,
                        hitPID: 42, focusedPID: 42, foregroundPID: 42))
        XCTAssertFalse(InputPolicy.canUseFocusedInput(at: CGPoint(x: 99, y: 250), bounds: bounds,
                        hitPID: 42, focusedPID: 42, foregroundPID: 42))
        XCTAssertFalse(InputPolicy.canUseFocusedInput(at: CGPoint(x: 200, y: 250), bounds: bounds,
                        hitPID: 43, focusedPID: 42, foregroundPID: 42))
        XCTAssertFalse(InputPolicy.canUseFocusedInput(at: CGPoint(x: 200, y: 250), bounds: bounds,
                        hitPID: 42, focusedPID: 42, foregroundPID: 43))
        XCTAssertFalse(InputPolicy.canUseFocusedInput(at: CGPoint(x: 200, y: 250), bounds: .zero,
                        hitPID: 42, focusedPID: 42, foregroundPID: 42))
    }
    func testReverseDragAndBoundaryClamp() {
        let rect = SelectionGeometry.selection(from: CGPoint(x: 90, y: 80), to: CGPoint(x: -20, y: -10),
                                               in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 90, height: 80))
    }
    func testRetinaSelectionUsesPixelCoordinates() {
        XCTAssertEqual(SelectionGeometry.pixels(for: CGRect(x: 10, y: 20, width: 100, height: 50),
                        logicalSize: CGSize(width: 800, height: 600), pixelSize: CGSize(width: 1600, height: 1200)),
                       CGRect(x: 20, y: 40, width: 200, height: 100))
    }
    func testNonRetinaFractionalSelectionEnclosesPixels() {
        XCTAssertEqual(SelectionGeometry.pixels(for: CGRect(x: 2.2, y: 3.7, width: 10.1, height: 5.2),
                        logicalSize: CGSize(width: 800, height: 600), pixelSize: CGSize(width: 800, height: 600)),
                       CGRect(x: 2, y: 3, width: 11, height: 6))
    }
    func testEmptySelectionIsRejected() {
        XCTAssertNil(SelectionGeometry.pixels(for: CGRect(x: 4, y: 4, width: 1, height: 40),
                     logicalSize: CGSize(width: 100, height: 100), pixelSize: CGSize(width: 200, height: 200)))
        XCTAssertNil(SelectionGeometry.pixels(for: CGRect(x: 200, y: 200, width: 20, height: 20),
                     logicalSize: CGSize(width: 100, height: 100), pixelSize: CGSize(width: 200, height: 200)))
    }
}

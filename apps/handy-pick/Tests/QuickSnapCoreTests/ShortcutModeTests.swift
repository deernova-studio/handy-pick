import XCTest
@testable import QuickSnapCore

final class ShortcutModeTests: XCTestCase {
    func testChordRequiresModifierAndValidKey() {
        for binding in [ShortcutBinding.mouse(2), .modifier(55), .key(35, 0)] {
            XCTAssertFalse(ShortcutMode.chord.accepts(binding))
            XCTAssertTrue(ShortcutMode.doublePress.accepts(binding))
        }
        for flag: UInt64 in [1 << 17, 1 << 18, 1 << 19, 1 << 20] {
            XCTAssertTrue(ShortcutMode.chord.accepts(.key(35, flag)))
            XCTAssertTrue(ShortcutMode.chord.accepts(.key(35, flag | (1 << 17))))
        }
        XCTAssertFalse(ShortcutMode.chord.accepts(.key(53, 1 << 20)))
    }
    func testShiftZRecordsAndTriggersInEditorsWithoutQueryingFocus() throws {
        let binding = ShortcutBinding.key(6, 1 << 17)
        XCTAssertTrue(ShortcutMode.chord.accepts(binding))
        XCTAssertTrue(binding.needsTypingProtection)
        XCTAssertEqual(try JSONDecoder().decode(ShortcutBinding.self, from: JSONEncoder().encode(binding)), binding)
        var gate = KeyPressGate()
        var recognizer = ShortcutRecognizer(interval: 0.4)
        XCTAssertEqual(gate.down(binding: binding, code: 6, flags: 1 << 17, repeating: false, allowShortcut: true), .press)
        XCTAssertNotNil(recognizer.press(mode: .chord, at: 1, point: .zero, target: 42))
        XCTAssertEqual(gate.up(code: 6), .consume)
        var focusQueries = 0
        func editorOrUnavailable() -> Bool { focusQueries += 1; return false }
        let allowed = ShortcutMode.chord.allowsActivation(for: binding, focusAllowsShortcut: editorOrUnavailable())
        XCTAssertTrue(allowed); XCTAssertEqual(focusQueries, 0)
        XCTAssertEqual(gate.down(binding: binding, code: 6, flags: 1 << 17, repeating: false, allowShortcut: allowed), .press)
        XCTAssertNotNil(recognizer.press(mode: .chord, at: 2, point: .zero, target: 42))
        XCTAssertEqual(gate.down(binding: binding, code: 6, flags: 1 << 17, repeating: true, allowShortcut: allowed), .consume)
        XCTAssertEqual(gate.up(code: 6), .consume)
    }
    func testDoublePressTypingProtectionStillApplies() {
        for binding in [ShortcutBinding.key(35, 0), .key(6, 1 << 17)] {
            XCTAssertFalse(ShortcutMode.doublePress.allowsActivation(for: binding, focusAllowsShortcut: false))
            XCTAssertTrue(ShortcutMode.doublePress.allowsActivation(for: binding, focusAllowsShortcut: true))
        }
        XCTAssertFalse(ShortcutMode.chord.allowsActivation(for: .key(35, 0), focusAllowsShortcut: true))
    }
    func testMouseDoublePressNeverQueriesTypingFocus() {
        func shouldNotQuery() -> Bool { XCTFail("Mouse must bypass typing protection"); return false }
        XCTAssertTrue(ShortcutMode.doublePress.allowsActivation(for: .mouse(2), focusAllowsShortcut: shouldNotQuery()))
        XCTAssertTrue(ShortcutMode.doublePress.allowsActivation(for: .mouse(3), focusAllowsShortcut: shouldNotQuery()))
    }
    func testSingleChordPressAndHoldOnlyDispatchOnceUntilRelease() {
        var gate = KeyPressGate()
        var recognizer = ShortcutRecognizer(interval: 0.4)
        let binding = ShortcutBinding.key(35, 1 << 19)
        var actions = 0
        for index in 0..<6 {
            if gate.down(binding: binding, code: 35, flags: 1 << 19, repeating: index > 0) == .press {
                if recognizer.press(mode: .chord, at: Double(index), point: .zero, target: 2) != nil { actions += 1 }
            }
        }
        XCTAssertEqual(actions, 1)
        XCTAssertEqual(gate.up(code: 35), .consume)
        XCTAssertEqual(gate.down(binding: binding, code: 35, flags: 1 << 19, repeating: false), .press)
        XCTAssertNotNil(recognizer.press(mode: .chord, at: 7, point: .zero, target: 2))
    }
    func testDoubleModeStillRequiresTwoPressesAndSwitchClearsPendingClick() {
        var recognizer = ShortcutRecognizer(interval: 0.4)
        XCTAssertNil(recognizer.press(mode: .doublePress, at: 1, point: .zero, target: 2))
        XCTAssertNotNil(recognizer.press(mode: .doublePress, at: 1.1, point: .zero, target: 2))
        XCTAssertNil(recognizer.press(mode: .doublePress, at: 1.2, point: .zero, target: 2))
        XCTAssertNotNil(recognizer.press(mode: .chord, at: 1.3, point: .zero, target: 2))
        XCTAssertNil(recognizer.press(mode: .doublePress, at: 1.4, point: .zero, target: 2))
        recognizer.cancel()
        XCTAssertNil(recognizer.press(mode: .doublePress, at: 1.5, point: .zero, target: 2))
    }
}

import XCTest
@testable import QuickSnapCore

final class ShortcutModeTests: XCTestCase {
    func testChordRequiresCommandControlOrOptionAndValidKey() {
        for binding in [ShortcutBinding.mouse(2), .modifier(55), .key(35, 0), .key(35, 1 << 17)] {
            XCTAssertFalse(ShortcutMode.chord.accepts(binding))
            XCTAssertTrue(ShortcutMode.doublePress.accepts(binding))
        }
        for flag: UInt64 in [1 << 18, 1 << 19, 1 << 20] {
            XCTAssertTrue(ShortcutMode.chord.accepts(.key(35, flag)))
            XCTAssertTrue(ShortcutMode.chord.accepts(.key(35, flag | (1 << 17))))
        }
        XCTAssertFalse(ShortcutMode.chord.accepts(.key(53, 1 << 20)))
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

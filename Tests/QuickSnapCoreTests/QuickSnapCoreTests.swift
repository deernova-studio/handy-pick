import XCTest
import CoreGraphics
@testable import QuickSnapCore

final class QuickSnapCoreTests: XCTestCase {
    func testSingleWaitsForDoubleClickWindow() {
        var gesture = ClickRecognizer(interval: 0.3)
        XCTAssertEqual(gesture.press(at: 10, point: .zero, target: 42), [.cancelSingle, .scheduleSingle(10.3)])
        XCTAssertNil(gesture.singleDue(at: 10.2))
        XCTAssertEqual(gesture.singleDue(at: 10.31), .capture(42))
        XCTAssertNil(gesture.singleDue(at: 11))
    }
    func testDoubleClickPastesOnceAndNeverCaptures() {
        var gesture = ClickRecognizer(interval: 0.4)
        _ = gesture.press(at: 10, point: CGPoint(x: 50, y: 80), target: 42)
        XCTAssertEqual(gesture.press(at: 10.15, point: CGPoint(x: 52, y: 81), target: 42), [.cancelSingle, .paste(42)])
        XCTAssertNil(gesture.singleDue(at: 11))
    }
    func testChangedAppCannotReceiveDoubleClickPaste() {
        var gesture = ClickRecognizer(interval: 0.4)
        _ = gesture.press(at: 10, point: .zero, target: 42)
        XCTAssertEqual(gesture.press(at: 10.1, point: .zero, target: 43), [.cancelSingle, .scheduleSingle(10.5)])
        XCTAssertEqual(gesture.singleDue(at: 10.6), .capture(43))
    }
    func testDistantClicksDoNotPaste() {
        var gesture = ClickRecognizer(interval: 0.4)
        _ = gesture.press(at: 10, point: .zero, target: 42)
        let result = gesture.press(at: 10.1, point: CGPoint(x: 100, y: 100), target: 42)
        XCTAssertEqual(result, [.cancelSingle, .scheduleSingle(10.5)])
    }
    func testPauseOrDragCancelsPendingCapture() {
        var gesture = ClickRecognizer(interval: 0.4)
        _ = gesture.press(at: 10, point: .zero, target: 42)
        gesture.cancel()
        XCTAssertNil(gesture.singleDue(at: 11))
        XCTAssertEqual(gesture.press(at: 12, point: .zero, target: 42), [.cancelSingle, .scheduleSingle(12.4)])
    }
    func testSlowClicksAreNotDoubleClicks() {
        var gesture = ClickRecognizer(interval: 0.3)
        _ = gesture.press(at: 1, point: .zero, target: 42)
        XCTAssertEqual(gesture.singleDue(at: 1.31), .capture(42))
        XCTAssertEqual(gesture.press(at: 2, point: .zero, target: 42), [.cancelSingle, .scheduleSingle(2.3)])
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

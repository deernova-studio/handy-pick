import XCTest
import CoreGraphics
@testable import QuickSnapCore

final class SelectionResizeTests: XCTestCase {
    let bounds = CGRect(x: 0, y: 0, width: 720, height: 480)
    let rect = CGRect(x: 100, y: 80, width: 400, height: 300)

    func testAllEightHandlesKeepOppositeEdgesFixed() {
        let expected: [(SelectionGeometry.Handle, CGRect)] = [
            (.left, CGRect(x: 120, y: 80, width: 380, height: 300)),
            (.right, CGRect(x: 100, y: 80, width: 420, height: 300)),
            (.top, CGRect(x: 100, y: 110, width: 400, height: 270)),
            (.bottom, CGRect(x: 100, y: 80, width: 400, height: 330)),
            (.topLeft, CGRect(x: 120, y: 110, width: 380, height: 270)),
            (.topRight, CGRect(x: 100, y: 110, width: 420, height: 270)),
            (.bottomLeft, CGRect(x: 120, y: 80, width: 380, height: 330)),
            (.bottomRight, CGRect(x: 100, y: 80, width: 420, height: 330))
        ]
        for (handle, result) in expected {
            XCTAssertEqual(SelectionGeometry.handle(at: handle.point(on: rect), on: rect), handle)
            XCTAssertEqual(SelectionGeometry.resized(rect, handle: handle, delta: CGPoint(x: 20, y: 30), in: bounds), result)
        }
        XCTAssertNil(SelectionGeometry.handle(at: CGPoint(x: 300, y: 200), on: rect))
        XCTAssertEqual(SelectionGeometry.handle(at: CGPoint(x: 503, y: 200), on: rect), .right)
        XCTAssertNil(SelectionGeometry.handle(at: CGPoint(x: 510, y: 200), on: rect))
    }
    func testResizeClampsToScreenAndCannotCollapseOrFlip() {
        XCTAssertEqual(SelectionGeometry.resized(rect, handle: .topLeft, delta: CGPoint(x: -1000, y: -1000), in: bounds), CGRect(x: 0, y: 0, width: 500, height: 380))
        XCTAssertEqual(SelectionGeometry.resized(rect, handle: .bottomRight, delta: CGPoint(x: 1000, y: 1000), in: bounds), CGRect(x: 100, y: 80, width: 620, height: 400))
        for (handle, delta) in [(SelectionGeometry.Handle.topLeft, CGPoint(x: 1000, y: 1000)), (.bottomRight, CGPoint(x: -1000, y: -1000))] {
            let result = SelectionGeometry.resized(rect, handle: handle, delta: delta, in: bounds)
            XCTAssertEqual(result.size, CGSize(width: 3, height: 3))
            XCTAssertNotNil(SelectionGeometry.pixels(for: result, logicalSize: bounds.size, pixelSize: CGSize(width: 1440, height: 960)))
        }
    }
}

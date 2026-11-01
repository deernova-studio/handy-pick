import XCTest
import AppKit
@testable import QuickSnapCore

final class HistoryAndAnnotationTests: XCTestCase {
    func testHistoryDeduplicatesAndMovesExistingItemToFront() {
        var history = ClipboardHistory()
        XCTAssertTrue(history.insert(.text("一段文字 🦌")))
        let firstID = history.entries[0].id
        XCTAssertFalse(history.insert(.text("一段文字 🦌")))
        history.insert(.text("another")); history.insert(.text("一段文字 🦌"))
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertEqual(history.entries[0].id, firstID)
        XCTAssertEqual(history.byteCount, "一段文字 🦌another".utf8.count)
    }
    func testHistoryEvictsOldestByCountAndBytesWithoutDestroyingOnOversize() {
        var history = ClipboardHistory(maximumCount: 2, maximumBytes: 8)
        history.insert(.text("old")); history.insert(.text("next")); history.insert(.text("new"))
        XCTAssertEqual(history.entries.map(\.content), [.text("new"), .text("next")])
        XCTAssertFalse(history.insert(.image(Data(repeating: 0, count: 9), type: "public.png")))
        XCTAssertEqual(history.entries.count, 2)
        history.insert(.text("12345678"))
        XCTAssertEqual(history.entries.count, 1); XCTAssertEqual(history.byteCount, 8)
    }
    func testDeleteClearAndNewSession() {
        var history = ClipboardHistory()
        history.insert(.image(Data([1,2,3]), type: "public.png")); history.insert(.text(" "))
        history.remove(history.entries.last!.id)
        XCTAssertEqual(history.byteCount, 1)
        history.clear(); XCTAssertTrue(history.entries.isEmpty); XCTAssertEqual(history.byteCount, 0)
        history.insert(.text("fresh")); XCTAssertTrue(ClipboardHistory().entries.isEmpty)
    }
    private func fixture() -> CGImage {
        let ctx = CGContext(data: nil, width: 200, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
        // Top-left blue block distinguishes flips and shifted crops.
        ctx.setFillColor(NSColor.blue.cgColor); ctx.fill(CGRect(x: 0, y: 100, width: 20, height: 20))
        return ctx.makeImage()!
    }
    private func color(_ image: CGImage, _ x: Int, _ y: Int) -> NSColor {
        NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
    }
    func testAnnotationRetinaScaleAndTopLeftOrientation() {
        let image = fixture()
        let result = AnnotationRenderer.render(image: image, selection: CGRect(x: 0, y: 0, width: 80, height: 50), logicalSize: CGSize(width: 100, height: 60), annotations: [
            Annotation(kind: .line, start: CGPoint(x: 20, y: 15), end: CGPoint(x: 60, y: 15), color: .red)
        ])!
        XCTAssertEqual(result.width, 160); XCTAssertEqual(result.height, 100)
        XCTAssertGreaterThan(color(result, 5, 5).blueComponent, 0.9)
        XCTAssertLessThan(color(result, 5, 5).redComponent, 0.1)
        XCTAssertGreaterThan(color(result, 80, 30).redComponent, 0.9)
        XCTAssertLessThan(color(result, 80, 30).greenComponent, 0.1)
        XCTAssertGreaterThan(color(result, 80, 80).greenComponent, 0.9)
    }
    func testOffsetCropClipsAnnotationsAndKeepsEllipseHollow() {
        let result = AnnotationRenderer.render(image: fixture(), selection: CGRect(x: 20, y: 10, width: 50, height: 40), logicalSize: CGSize(width: 100, height: 60), annotations: [
            Annotation(kind: .ellipse, start: CGPoint(x: 30, y: 20), end: CGPoint(x: 60, y: 40), color: .red),
            Annotation(kind: .line, start: CGPoint(x: 0, y: 12), end: CGPoint(x: 90, y: 12), color: .red)
        ])!
        XCTAssertEqual(result.width, 100); XCTAssertEqual(result.height, 80)
        XCTAssertLessThan(color(result, 50, 20).greenComponent, 0.2) // ellipse top
        XCTAssertGreaterThan(color(result, 50, 40).greenComponent, 0.9) // hollow middle
        XCTAssertLessThan(color(result, 5, 4).greenComponent, 0.2) // clipped line
    }
    func testTextRendersInsideCropAndEmptyAnnotationsPreservePixels() {
        let image = fixture(), selection = CGRect(x: 0, y: 0, width: 100, height: 60)
        let plain = AnnotationRenderer.render(image: image, selection: selection, logicalSize: selection.size, annotations: [])!
        XCTAssertEqual(plain.dataProvider!.data! as Data, image.dataProvider!.data! as Data)
        let result = AnnotationRenderer.render(image: image, selection: selection, logicalSize: selection.size, annotations: [
            Annotation(kind: .text, start: CGPoint(x: 20, y: 15), end: .zero, text: "Hi", color: .red)
        ])!
        var redPixels = 0
        for y in 30..<90 { for x in 40..<130 {
            let c = color(result, x, y)
            if c.redComponent > 0.8 && c.greenComponent < 0.3 { redPixels += 1 }
        } }
        XCTAssertGreaterThan(redPixels, 100)
    }
}

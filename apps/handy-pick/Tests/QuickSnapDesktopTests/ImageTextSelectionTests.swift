import XCTest
import AppKit
import VisionKit
@testable import QuickSnap

final class ImageTextSelectionTests: XCTestCase {
    @MainActor func testLiveTextRecognizesAndCopiesOnlySelectedRange() async throws {
        guard ImageAnalyzer.isSupported else { throw XCTSkip("Live Text unavailable on this host") }
        _ = NSApplication.shared
        let view = ImageTextSelection(image: fixture(), frame: NSRect(x: 0, y: 0, width: 720, height: 280))
        let window = NSPanel(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { view.stop(); window.close() }
        for _ in 0..<200 {
            if view.recognitionFinished { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(view.recognitionFinished)
        XCTAssertTrue(view.recognizedText.contains("HandyPick"), view.recognizedText)
        XCTAssertTrue(view.recognizedText.contains("2026"), view.recognizedText)
        XCTAssertTrue(view.recognizedText.contains("文字识别"), view.recognizedText)
        let pb = NSPasteboard.withUniqueName(); defer { pb.releaseGlobally() }
        pb.setString("unchanged", forType: .string)
        XCTAssertFalse(view.copyText(allIfUnselected: false, pasteboard: pb))
        XCTAssertEqual(pb.string(forType: .string), "unchanged")
        XCTAssertTrue(view.copyText(allIfUnselected: true, pasteboard: pb))
        XCTAssertEqual(pb.string(forType: .string), view.recognizedText)
        let range = try XCTUnwrap(view.overlay.text.range(of: "HandyPick"))
        view.overlay.selectedRanges = [range]
        XCTAssertEqual(view.overlay.selectedText, "HandyPick")
        XCTAssertTrue(view.copyText(allIfUnselected: true, pasteboard: pb))
        XCTAssertEqual(pb.string(forType: .string), "HandyPick")
    }

    @MainActor func testLeavingOCRCancelsPendingAnalysisAndRestoresImageEditing() {
        _ = NSApplication.shared
        let content = HistoryImageEditor(image: fixture(), size: NSSize(width: 720, height: 480))
        let panel = NSPanel(contentRect: content.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.contentView = content; defer { panel.close() }
        let buttons = content.toolbar.content.subviews.compactMap { $0 as? NSButton }
        let ocr = buttons.first { $0.tag == 6 }!
        ocr.performClick(nil)
        XCTAssertNotNil(content.editor.textSelection)
        XCTAssertEqual(ocr.state, .on)
        panel.setContentSize(NSSize(width: 900, height: 600)); content.layoutSubtreeIfNeeded()
        XCTAssertEqual(content.editor.textSelection?.frame, content.editor.bounds)
        buttons.first { $0.tag == 2 }!.performClick(nil)
        XCTAssertNil(content.editor.textSelection)
        XCTAssertEqual(ocr.state, .off)
        var result: CGImage?
        content.editor.onComplete = { result = $0 }
        buttons.first { $0.tag == 5 }!.performClick(nil)
        XCTAssertEqual(result?.width, 720); XCTAssertEqual(result?.height, 280)
    }

    @MainActor func testEmptyImageDoesNotOverwriteClipboard() async throws {
        guard ImageAnalyzer.isSupported else { throw XCTSkip("Live Text unavailable on this host") }
        _ = NSApplication.shared
        let image = NSImage(size: NSSize(width: 200, height: 120), flipped: false) { _ in
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 200, height: 120).fill(); return true
        }.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let view = ImageTextSelection(image: image, frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        defer { view.stop() }
        for _ in 0..<200 {
            if view.recognitionFinished { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(view.recognitionFinished); XCTAssertTrue(view.recognizedText.isEmpty)
        let pb = NSPasteboard.withUniqueName(); defer { pb.releaseGlobally() }
        pb.setString("keep", forType: .string)
        XCTAssertFalse(view.copyText(allIfUnselected: true, pasteboard: pb))
        XCTAssertEqual(pb.string(forType: .string), "keep")
    }

    @MainActor private func fixture() -> CGImage {
        let image = NSImage(size: NSSize(width: 720, height: 280), flipped: false) { _ in
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 720, height: 280).fill()
            ("HandyPick Live Text 2026" as NSString).draw(at: NSPoint(x: 40, y: 170), withAttributes: [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black])
            ("随取文字识别测试" as NSString).draw(at: NSPoint(x: 40, y: 100), withAttributes: [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black])
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}

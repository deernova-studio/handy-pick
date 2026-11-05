import XCTest
import AppKit
import QuickSnapCore
@testable import QuickSnap

final class ClipboardAndEditorTests: XCTestCase {
    @MainActor func testSessionBaselineSelectionClearAndPrivacyMarker() {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.setString("before launch", forType: .string)
        let monitor = ClipboardMonitor(pasteboard: pb)
        monitor.start(); defer { monitor.stop() }
        monitor.poll(); XCTAssertTrue(monitor.history.entries.isEmpty)
        pb.clearContents(); pb.setString("fresh text", forType: .string); monitor.poll()
        XCTAssertEqual(monitor.history.entries.count, 1)
        let first = monitor.history.entries[0].id
        pb.clearContents(); pb.setString("second", forType: .string); monitor.poll()
        XCTAssertTrue(monitor.select(first))
        XCTAssertEqual(pb.string(forType: .string), "fresh text")
        XCTAssertEqual(monitor.history.entries[0].id, first)
        pb.clearContents(); pb.setString("private fixture", forType: .string)
        pb.setData(Data(), forType: .init("org.nspasteboard.ConcealedType")); monitor.poll()
        XCTAssertEqual(monitor.history.entries.count, 2)
        monitor.clear(); monitor.poll(); XCTAssertTrue(monitor.history.entries.isEmpty)
        XCTAssertEqual(pb.string(forType: .string), "private fixture")
        monitor.stop(); monitor.start(); monitor.poll(); XCTAssertTrue(monitor.history.entries.isEmpty)
    }
    @MainActor func testPNGHistoryRoundTrip() {
        let pb = NSPasteboard.withUniqueName(); defer { pb.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: pb); monitor.start(); defer { monitor.stop() }
        let data = NSBitmapImageRep(cgImage: fixture()).representation(using: .png, properties: [:])!
        pb.clearContents(); pb.setData(data, forType: .png); monitor.poll()
        let id = monitor.history.entries[0].id
        pb.clearContents(); pb.setString("later", forType: .string); monitor.poll()
        XCTAssertTrue(monitor.select(id)); XCTAssertEqual(pb.data(forType: .png), data)
        XCTAssertNil(pb.string(forType: .string))
    }
    @MainActor func testSelectionWaitsForConfirmationAndPanelCoversFullFrame() {
        _ = NSApplication.shared
        let rect = NSRect(x: 0, y: 0, width: 720, height: 480)
        let panel = SelectionPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        XCTAssertEqual(panel.constrainFrameRect(rect, to: NSScreen.main), rect)
        let view = SelectionView(image: fixture()); panel.contentView = view
        var result: CGImage?
        view.onComplete = { result = $0 }
        view.mouseDown(with: mouse(.leftMouseDown, x: 80, y: 380))
        view.mouseUp(with: mouse(.leftMouseUp, x: 600, y: 120))
        XCTAssertNil(result)
        let bar = view.subviews.compactMap { $0 as? PaperlightGlass }.first!
        let buttons = bar.content.subviews.compactMap { $0 as? NSButton }.sorted { $0.tag < $1.tag }
        XCTAssertEqual(buttons.count, 7)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(bar.content.frame.size, bar.bounds.size)
        view.mouseDown(with: mouse(.leftMouseDown, x: 150, y: 250))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 400, y: 250))
        view.mouseUp(with: mouse(.leftMouseUp, x: 400, y: 250))
        buttons.first { $0.tag == 1 }!.performClick(nil)
        view.mouseDown(with: mouse(.leftMouseDown, x: 160, y: 320))
        view.mouseUp(with: mouse(.leftMouseUp, x: 300, y: 160))
        buttons.first { $0.tag == 2 }!.performClick(nil)
        view.mouseDown(with: mouse(.leftMouseDown, x: 330, y: 300))
        view.subviews.compactMap { $0 as? NSTextField }.first!.stringValue = "标注示例"
        // Switching tools commits the active text edit before export.
        buttons.first { $0.tag == 0 }!.performClick(nil)
        view.appearance = NSAppearance(named: .aqua)
        savePreview(view, "annotation-editor.png")
        savePreview(bar.content, "annotation-controls.png")
        view.appearance = NSAppearance(named: .darkAqua)
        savePreview(view, "annotation-editor-dark.png")
        savePreview(bar.content, "annotation-controls-dark.png")
        buttons.first { $0.tag == 5 }!.performClick(nil)
        XCTAssertEqual(result?.width, 520); XCTAssertEqual(result?.height, 260)
    }
    @MainActor func testCropResizePreservesAnnotationsAndRepositionsExistingToolbar() {
        _ = NSApplication.shared
        let panel = SelectionPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; defer { panel.close() }
        let view = SelectionView(image: fixture()); panel.contentView = view
        func event(_ kind: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
            let point = view.convert(CGPoint(x: x, y: y), to: nil)
            return mouse(kind, x: point.x, y: point.y)
        }
        func drag(_ x: CGFloat, _ y: CGFloat, _ endX: CGFloat, _ endY: CGFloat) {
            view.mouseDown(with: event(.leftMouseDown, x, y))
            view.mouseDragged(with: event(.leftMouseDragged, endX, endY))
            view.mouseUp(with: event(.leftMouseUp, endX, endY))
        }
        drag(80, 100, 600, 360)
        let bar = view.subviews.compactMap { $0 as? PaperlightGlass }.first!
        let buttons = bar.content.subviews.compactMap { $0 as? NSButton }.sorted { $0.tag < $1.tag }
        var result: CGImage?
        view.onComplete = { result = $0 }
        drag(150, 200, 400, 200)
        buttons[5].performClick(nil)
        let annotated = result!.dataProvider!.data! as Data
        let originalBarFrame = bar.frame
        // Start a few points outside the edge: no jump, no accidental annotation.
        view.mouseDown(with: event(.leftMouseDown, 603, 230))
        XCTAssertTrue(bar.isHidden)
        view.mouseDragged(with: event(.leftMouseDragged, 303, 230))
        view.mouseUp(with: event(.leftMouseUp, 303, 230))
        XCTAssertFalse(bar.isHidden)
        buttons[5].performClick(nil)
        XCTAssertEqual(result?.width, 220); XCTAssertEqual(result?.height, 260)
        XCTAssertNotEqual(bar.frame, originalBarFrame)
        drag(303, 230, 603, 230)
        buttons[5].performClick(nil)
        XCTAssertEqual(result!.dataProvider!.data! as Data, annotated, "Shrinking and expanding must retain annotations at original coordinates")
        // Corner resize with the text tool selected must not start a text field.
        buttons[2].performClick(nil)
        drag(80, 100, 40, 60)
        XCTAssertTrue(view.subviews.compactMap { $0 as? NSTextField }.isEmpty)
        XCTAssertEqual(buttons[2].state, .on)
        buttons[5].performClick(nil)
        XCTAssertEqual(result?.width, 560); XCTAssertEqual(result?.height, 300)
        XCTAssertEqual(view.subviews.compactMap { $0 as? PaperlightGlass }.count, 1)
        savePreview(view, "resizable-crop.png")
        // Undo still removes the original line; resizing is not an annotation.
        buttons[3].performClick(nil); buttons[5].performClick(nil)
        let clean = AnnotationRenderer.render(image: view.image, selection: CGRect(x: 40, y: 60, width: 560, height: 300), logicalSize: view.bounds.size, annotations: [])!
        XCTAssertEqual(result!.dataProvider!.data! as Data, clean.dataProvider!.data! as Data)
    }
    @MainActor func testHistoryGridContainsSettingsAndSelectableCards() {
        _ = NSApplication.shared
        let panel = ShortcutPopover(); panel.loadViewIfNeeded()
        panel.view.appearance = NSAppearance(named: .aqua)
        panel.update(binding: "鼠标中键", recording: false, needsPermission: false)
        XCTAssertEqual(panel.preferredContentSize, NSSize(width: 240, height: 56))
        var history = ClipboardHistory()
        let data = NSBitmapImageRep(cgImage: fixture()).representation(using: .png, properties: [:])!
        for text in ["A tiny helper for everyday ideas.", "把灵感随手收好。", "HandyPick", "⌘ C → 双击 → 粘贴", "A longer note with enough text to wrap across several lines in the card."] { history.insert(.text(text)) }
        history.insert(.image(data, type: NSPasteboard.PasteboardType.png.rawValue))
        panel.updateHistory(history.entries)
        let scroll = panel.view.subviews.compactMap { $0 as? NSScrollView }.first!
        XCTAssertFalse(scroll.isHidden)
        XCTAssertEqual(panel.preferredContentSize, NSSize(width: 360, height: 312))
        XCTAssertEqual(scroll.documentView?.subviews.count, 6)
        var selected: UUID?
        panel.onSelect = { selected = $0 }
        (scroll.documentView!.subviews.first as! NSButton).performClick(nil)
        XCTAssertEqual(selected, history.entries[0].id)
        savePreview(panel.view, "clipboard-panel.png")
        panel.view.appearance = NSAppearance(named: .darkAqua)
        savePreview(panel.view, "clipboard-panel-dark.png")
        for index in 7...10 { history.insert(.text("History fixture \(index)")) }
        for (count, height) in [(1, 192), (3, 192), (4, 312), (6, 312), (7, 432), (9, 432), (10, 432)] {
            panel.updateHistory(Array(history.entries.prefix(count)))
            XCTAssertEqual(panel.preferredContentSize.height, CGFloat(height))
            XCTAssertEqual(scroll.hasVerticalScroller, count > 9)
        }
        XCTAssertGreaterThan(scroll.documentView!.frame.height, scroll.contentSize.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
        panel.updateHistory(Array(history.entries.prefix(1)))
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 0)
        savePreview(panel.view, "clipboard-one-row.png")
        panel.updateHistory([])
        XCTAssertTrue(scroll.isHidden)
        XCTAssertEqual(scroll.documentView?.subviews.count, 0)
        XCTAssertEqual(panel.preferredContentSize, NSSize(width: 240, height: 56))
        savePreview(panel.view, "clipboard-empty-dark.png")
    }
    @MainActor func testHistoryTypeFiltersPreserveEntryActionsAndResetWhenEmpty() {
        _ = NSApplication.shared
        let panel = ShortcutPopover()
        var history = ClipboardHistory()
        for index in 0..<11 { history.insert(.text("Text \(index)")) }
        let png = NSBitmapImageRep(cgImage: fixture()).representation(using: .png, properties: [:])!
        history.insert(.image(png, type: NSPasteboard.PasteboardType.png.rawValue))
        let imageID = history.entries[0].id
        panel.updateHistory(history.entries)
        let filter = panel.view.subviews.first { $0.identifier?.rawValue == "historyTypeFilter" } as! NSSegmentedControl
        let mode = panel.view.subviews.compactMap { $0 as? NSPopUpButton }.first!
        let binding = panel.view.subviews.compactMap { $0 as? NSButton }.first { !($0 is NSPopUpButton) }!
        for control in [mode as NSView, binding, filter] {
            let visual = control.alignmentRect(forFrame: control.frame)
            XCTAssertEqual(visual.height, 24, accuracy: 0.01)
            XCTAssertEqual(visual.midY, 28, accuracy: 0.01)
        }
        let scroll = panel.view.subviews.compactMap { $0 as? NSScrollView }.first!
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
        func select(_ index: Int) {
            filter.selectedSegment = index; filter.sendAction(filter.action, to: filter.target)
        }
        select(1)
        XCTAssertEqual(scroll.documentView?.subviews.count, 1)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 0)
        XCTAssertEqual(panel.preferredContentSize.height, 192)
        var copied: UUID?; var previewed: UUID?
        panel.onSelect = { copied = $0 }; panel.onPreview = { previewed = $0 }
        let tile = scroll.documentView!.subviews.first as! HistoryTile
        tile.performClick(nil)
        (tile.subviews.first as! NSButton).performClick(nil)
        XCTAssertEqual(copied, imageID); XCTAssertEqual(previewed, imageID)
        select(2)
        XCTAssertEqual(scroll.documentView?.subviews.count, 11)
        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertEqual(panel.preferredContentSize.height, 432)
        history.insert(.text("Newest text")); panel.updateHistory(history.entries)
        XCTAssertEqual(filter.selectedSegment, 2)
        select(1)
        panel.updateHistory(history.entries.filter { $0.id != imageID })
        XCTAssertEqual(filter.selectedSegment, 0)
        XCTAssertFalse(filter.isEnabled(forSegment: 1))
        panel.updateHistory([])
        XCTAssertTrue(filter.isHidden)
        XCTAssertEqual(panel.preferredContentSize, NSSize(width: 240, height: 56))
    }
    @MainActor func testPreviewButtonDoesNotCopyAndHoverRevealsIt() {
        _ = NSApplication.shared
        var history = ClipboardHistory(); history.insert(.text("Preview without changing clipboard"))
        let panel = ShortcutPopover(); panel.updateHistory(history.entries)
        let scroll = panel.view.subviews.compactMap { $0 as? NSScrollView }.first!
        let tile = scroll.documentView!.subviews.first as! HistoryTile
        let expand = tile.subviews.compactMap { $0 as? NSButton }.sorted { $0.tag < $1.tag }.first!
        var copied = false; var previewed: UUID?
        panel.onSelect = { _ in copied = true }; panel.onPreview = { previewed = $0 }
        XCTAssertTrue(expand.isHidden)
        tile.mouseEntered(with: mouse(.mouseMoved, x: 50, y: 50))
        XCTAssertFalse(expand.isHidden)
        tile.layoutSubtreeIfNeeded()
        let hit = tile.hitTest(NSPoint(x: tile.frame.minX+expand.frame.midX, y: tile.frame.minY+expand.frame.midY))
        XCTAssertTrue(hit === expand, "Preview button must receive mouse clicks instead of the copy action")
        expand.performClick(nil)
        XCTAssertFalse(copied); XCTAssertEqual(previewed, history.entries[0].id)
        savePreview(panel.view, "clipboard-hover-preview.png")
        tile.mouseExited(with: mouse(.mouseMoved, x: 150, y: 150))
        XCTAssertTrue(expand.isHidden)
        tile.performClick(nil); XCTAssertTrue(copied)
    }
    @MainActor func testPreviewPreservesFullTextAndOriginalImageAndClearsOnHistoryRemoval() {
        _ = NSApplication.shared
        let text = String(repeating: "完整文字预览，支持滚动。\n", count: 200)
        let size = NSSize(width: 640, height: 480)
        let root = HistoryPreview.contentView(for: .text(text), size: size)
        let scroll = root.subviews.first as! NSScrollView
        let editor = scroll.documentView as! NSTextView
        XCTAssertEqual(editor.string, text); XCTAssertFalse(editor.isEditable); XCTAssertTrue(editor.isSelectable)
        let png = NSBitmapImageRep(cgImage: fixture()).representation(using: .png, properties: [:])!
        let imageRoot = HistoryPreview.contentView(for: .image(png, type: NSPasteboard.PasteboardType.png.rawValue), size: size)
        let image = (imageRoot as! HistoryImageEditor).editor.image
        XCTAssertEqual(image.width, 720); XCTAssertEqual(image.height, 480)
        savePreview(imageRoot, "history-image-preview.png")
        savePreview(root, "history-text-preview.png")
        var history = ClipboardHistory(); history.insert(.text(text))
        let preview = HistoryPreview(); var closed = false; preview.onDismiss = { closed = true }
        preview.show(history.entries[0])
        XCTAssertNotNil(preview.window)
        preview.retainOnly(Set(history.entries.map(\.id)))
        XCTAssertNotNil(preview.window)
        preview.retainOnly([])
        XCTAssertNil(preview.window); XCTAssertNil(preview.entryID); XCTAssertTrue(closed)
    }
    @MainActor func testHistoryImageAnnotationKeepsResolutionAndSurvivesResize() {
        _ = NSApplication.shared
        let content = HistoryImageEditor(image: fixture(), size: NSSize(width: 640, height: 480))
        let window = NSPanel(contentRect: content.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = content
        defer { window.close() }
        let editor = content.editor
        let buttons = content.toolbar.content.subviews.compactMap { $0 as? NSButton }.sorted { $0.tag < $1.tag }
        XCTAssertEqual(buttons.count, 6)
        XCTAssertEqual(buttons[2].title, "T"); XCTAssertTrue((buttons[2] as! PaperlightButton).drawsTitleInsteadOfImage)
        var rendered: CGImage?
        editor.onComplete = { rendered = $0 }
        buttons[5].performClick(nil)
        let original = rendered!.dataProvider!.data! as Data
        func event(_ kind: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            let location = editor.convert(point, to: nil)
            return mouse(kind, x: location.x, y: location.y)
        }
        buttons[0].performClick(nil)
        editor.mouseDown(with: event(.leftMouseDown, CGPoint(x: 80, y: 80)))
        editor.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 400, y: 240)))
        editor.mouseUp(with: event(.leftMouseUp, CGPoint(x: 400, y: 240)))
        buttons[5].performClick(nil)
        XCTAssertEqual(rendered?.width, 720); XCTAssertEqual(rendered?.height, 480)
        let annotated = rendered!.dataProvider!.data! as Data
        XCTAssertNotEqual(annotated, original)
        let oldSize = editor.frame.size
        window.setContentSize(NSSize(width: 840, height: 600)); content.layoutSubtreeIfNeeded()
        XCTAssertNotEqual(editor.frame.size, oldSize)
        buttons[5].performClick(nil)
        XCTAssertEqual(rendered!.dataProvider!.data! as Data, annotated)
        savePreview(content, "history-image-annotation.png")
        buttons[3].performClick(nil); buttons[5].performClick(nil)
        XCTAssertEqual(rendered!.dataProvider!.data! as Data, original)
    }
    @MainActor func testModeSelectorKeepsCompactLayoutAndReportsSelection() {
        _ = NSApplication.shared
        let panel = ShortcutPopover()
        panel.update(binding: "⌃⌥P", recording: false, needsPermission: false, mode: .chord)
        let selector = panel.view.subviews.compactMap { $0 as? NSPopUpButton }.first!
        XCTAssertEqual(selector.indexOfSelectedItem, 2)
        XCTAssertTrue(selector.pullsDown)
        XCTAssertEqual(selector.item(at: 0)?.title, "组合键")
        XCTAssertEqual(selector.item(at: 0)?.isHidden, true)
        var selected: ShortcutMode?
        panel.onModeChange = { selected = $0 }
        selector.selectItem(at: 1)
        selector.sendAction(selector.action, to: selector.target)
        XCTAssertEqual(selected, .doublePress)
        XCTAssertEqual(panel.preferredContentSize, NSSize(width: 240, height: 56))
        panel.update(binding: "⌃⌥P", recording: false, needsPermission: false, mode: .chord)
        savePreview(panel.view, "shortcut-mode-chord.png")
    }
    private func fixture() -> CGImage {
        let c = CGContext(data: nil, width: 720, height: 480, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.94, alpha: 1).cgColor); c.fill(CGRect(x: 0, y: 0, width: 720, height: 480))
        c.setFillColor(NSColor.white.cgColor); c.fill(CGRect(x: 120, y: 150, width: 420, height: 200))
        c.setFillColor(NSColor.systemTeal.cgColor); c.fillEllipse(in: CGRect(x: 160, y: 220, width: 80, height: 80))
        return c.makeImage()!
    }
    private func mouse(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    @MainActor private func savePreview(_ view: NSView, _ name: String) {
        guard let path = ProcessInfo.processInfo.environment["HANDYPICK_PREVIEW_DIR"] else { return }
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path).appendingPathComponent(name))
    }
}

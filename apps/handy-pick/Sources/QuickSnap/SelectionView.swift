import AppKit
import VisionKit
import QuickSnapCore

final class SelectionView: NSView, NSTextFieldDelegate {
    static let toolbarWidth: CGFloat = 390
    private static let annotationTools: [Int: Annotation.Kind] = [0: .line, 1: .ellipse, 2: .text, 7: .rectangle, 8: .arrow]
    private(set) var textSelection: ImageTextSelection?
    var toolbarContentWidth: CGFloat { editsWholeImage ? 348 : Self.toolbarWidth }
    private var cachedAnalysis: ImageAnalysis?
    let image: CGImage
    private let editsWholeImage: Bool
    var onComplete: ((CGImage?) -> Void)?
    private var start: CGPoint?
    private var selection: CGRect = .zero
    private var editing = false
    private var resizeDrag: (handle: SelectionGeometry.Handle, origin: CGPoint, rect: CGRect)?
    private var moveDrag: (origin: CGPoint, rect: CGRect)?
    private var moveDidStart = false
    private var tool: Annotation.Kind?
    private var annotations: [Annotation] = []
    private var draft: Annotation?
    private var toolbar: PaperlightGlass?
    private var toolButtons: [NSButton] = []
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(image: CGImage, editsWholeImage: Bool = false) {
        self.image = image; self.editsWholeImage = editsWholeImage
        super.init(frame: .zero)
        editing = editsWholeImage
    }
    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        if editsWholeImage { selection = bounds; textSelection?.frame = bounds }
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        if textSelection != nil { addCursorRect(selection, cursor: .arrow) }
        if editing && !editsWholeImage {
            if tool == nil, textSelection == nil { addCursorRect(selection, cursor: .openHand) }
            for handle in SelectionGeometry.Handle.allCases.reversed() {
                addCursorRect(handle.hitRect(on: selection).intersection(bounds), cursor: cursor(for: handle))
            }
        }
        if let toolbar, !toolbar.isHidden { addCursorRect(toolbar.frame, cursor: .arrow) }
    }
    private func cursor(for handle: SelectionGeometry.Handle) -> NSCursor {
        switch handle {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case .topLeft, .bottomRight: return Self.nwseCursor
        case .topRight, .bottomLeft: return Self.neswCursor
        }
    }
    private static let nwseCursor = diagonalCursor(rising: false)
    private static let neswCursor = diagonalCursor(rising: true)
    private static func diagonalCursor(rising: Bool) -> NSCursor {
        // Public AppKit APIs only, including on macOS 14.
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            let path = NSBezierPath()
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: rising ? y : 24-y) }
            path.move(to: point(5, 5)); path.line(to: point(19, 19))
            path.move(to: point(5, 11)); path.line(to: point(5, 5)); path.line(to: point(11, 5))
            path.move(to: point(13, 19)); path.line(to: point(19, 19)); path.line(to: point(19, 13))
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.white.setStroke(); path.lineWidth = 4; path.stroke()
            NSColor.black.setStroke(); path.lineWidth = 2; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }
    override func draw(_ dirtyRect: NSRect) {
        let picture = NSImage(cgImage: image, size: bounds.size)
        picture.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        if !editsWholeImage { NSColor.black.withAlphaComponent(0.32).setFill(); bounds.fill() }
        if selection.width > 0, selection.height > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            picture.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            annotations.forEach { $0.draw() }; draft?.draw()
            NSGraphicsContext.restoreGraphicsState()
            if !editsWholeImage {
                NSColor.white.setStroke()
                let outline = NSBezierPath(rect: selection); outline.lineWidth = 1; outline.stroke()
                if editing {
                    for handle in SelectionGeometry.Handle.allCases {
                        let point = handle.point(on: selection)
                        let knob = NSBezierPath(ovalIn: CGRect(x: point.x-3, y: point.y-3, width: 6, height: 6))
                        NSColor.white.setFill(); knob.fill()
                        NSColor.black.withAlphaComponent(0.6).setStroke(); knob.lineWidth = 1; knob.stroke()
                    }
                }
            }
            if !editing {
                ("\(Int(selection.width)) × \(Int(selection.height))" as NSString).draw(at: CGPoint(x: selection.minX+6, y: max(6, selection.minY-26)),
                    withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white])
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        commitText()
        window?.makeKey(); window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if editing {
            if !editsWholeImage, let handle = SelectionGeometry.handle(at: point, on: selection) {
                endTextSelection()
                resizeDrag = (handle, point, selection)
                toolbar?.isHidden = true
                cursor(for: handle).set()
                window?.invalidateCursorRects(for: self)
                return
            }
            guard textSelection == nil, selection.contains(point) else { return }
            if tool == .text { beginText(at: point); return }
            // Match the toolbar checkmark. Leave text editing, Live Text and
            // resize handles to their own double-click interactions.
            if !editsWholeImage, event.clickCount == 2 {
                start = nil; draft = nil
                complete()
                return
            }
            if let tool {
                start = point; draft = Annotation(kind: tool, start: point, end: point)
            } else if !editsWholeImage {
                moveDrag = (point, selection)
                moveDidStart = false
            }
        } else { cachedAnalysis = nil; start = point; selection = .zero }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        if let drag = moveDrag {
            move(to: convert(event.locationInWindow, from: nil), drag: drag)
            if moveDidStart { NSCursor.closedHand.set() }; return
        }
        if let drag = resizeDrag {
            resize(to: convert(event.locationInWindow, from: nil), drag: drag)
            cursor(for: drag.handle).set()
            return
        }
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        if editing { draft?.end = clamped(point) }
        else { selection = SelectionGeometry.selection(from: start, to: point, in: bounds) }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let drag = moveDrag {
            move(to: convert(event.locationInWindow, from: nil), drag: drag)
            moveDrag = nil; moveDidStart = false
            showToolbar(); NSCursor.openHand.set(); return
        }
        if let drag = resizeDrag {
            resize(to: convert(event.locationInWindow, from: nil), drag: drag)
            resizeDrag = nil
            showToolbar()
            return
        }
        guard let start else { return }
        self.start = nil
        if editing {
            if var draft {
                draft.end = clamped(convert(event.locationInWindow, from: nil))
                if hypot(draft.end.x-draft.start.x, draft.end.y-draft.start.y) >= 2 {
                    cachedAnalysis = nil; annotations.append(draft)
                }
            }
            draft = nil; needsDisplay = true; return
        }
        selection = SelectionGeometry.selection(from: start, to: convert(event.locationInWindow, from: nil), in: bounds)
        guard SelectionGeometry.pixels(for: selection, logicalSize: bounds.size, pixelSize: CGSize(width: image.width, height: image.height)) != nil else {
            selection = .zero; needsDisplay = true; return
        }
        editing = true; showToolbar(); needsDisplay = true
    }
    private func resize(to point: CGPoint, drag: (handle: SelectionGeometry.Handle, origin: CGPoint, rect: CGRect)) {
        cachedAnalysis = nil
        selection = SelectionGeometry.resized(drag.rect, handle: drag.handle,
            delta: CGPoint(x: point.x-drag.origin.x, y: point.y-drag.origin.y), in: bounds)
        needsDisplay = true
    }
    private func move(to point: CGPoint, drag: (origin: CGPoint, rect: CGRect)) {
        if !moveDidStart {
            guard hypot(point.x-drag.origin.x, point.y-drag.origin.y) >= 3 else { return }
            moveDidStart = true; toolbar?.isHidden = true
        }
        let next = SelectionGeometry.moved(drag.rect,
            delta: CGPoint(x: point.x-drag.origin.x, y: point.y-drag.origin.y), in: bounds)
        let dx = next.minX-selection.minX, dy = next.minY-selection.minY
        if dx != 0 || dy != 0 { cachedAnalysis = nil }
        for index in annotations.indices {
            annotations[index].start.x += dx; annotations[index].start.y += dy
            annotations[index].end.x += dx; annotations[index].end.y += dy
        }
        selection = next; needsDisplay = true
    }
    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, selection.minX), selection.maxX), y: min(max(point.y, selection.minY), selection.maxY))
    }
    private func showToolbar() {
        let width = Self.toolbarWidth, height: CGFloat = 44
        var y = selection.maxY + 10
        if y + height > bounds.maxY - 8 { y = selection.minY - height - 10 }
        y = min(max(8, y), bounds.maxY-height-8)
        let x = min(max(8, selection.maxX-width), bounds.maxX-width-8)
        let bar = toolbar ?? makeToolbar()
        bar.frame = NSRect(x: x, y: y, width: width, height: height)
        if bar.superview == nil { addSubview(bar) }
        bar.isHidden = false; toolbar = bar; window?.invalidateCursorRects(for: self)
    }
    func makeToolbar() -> PaperlightGlass {
        let bar = PaperlightGlass(frame: NSRect(x: 0, y: 0, width: toolbarContentWidth, height: 44), radius: 22)
        let symbols = ["line.diagonal", "circle", "textformat", "arrow.uturn.backward", "xmark", "checkmark", "text.viewfinder", "rectangle", "arrow.up.right"]
        let labels = ["划线", "画圈", "文字", "撤销", "取消", editsWholeImage ? "复制图片" : "复制截图", "识别并选取文字", "方框", "箭头"]
        let items: [Int] = editsWholeImage ? [0, 7, 1, 8, 2, 3, 4, 5] : [0, 7, 1, 8, 2, 6, 3, 4, 5]
        for (position, index) in items.enumerated() {
            let button = PaperlightButton(image: NSImage(systemSymbolName: symbols[index], accessibilityDescription: labels[index])!, target: self, action: #selector(toolbarClicked(_:)))
            if index == 2 { button.image = nil; button.drawsTitleInsteadOfImage = true; button.title = "T"; button.font = .systemFont(ofSize: 18, weight: .semibold) }
            button.frame = NSRect(x: 8 + CGFloat(position)*42, y: 4, width: 36, height: 36)
            button.tag = index; button.isBordered = false; button.cornerRadius = 18; button.toolTip = labels[index]
            button.setAccessibilityLabel(labels[index]); button.setButtonType(Self.annotationTools[index] != nil || index == 6 ? .toggle : .momentaryPushIn)
            button.style = index == 5 ? .primary : .plain
            button.isOnGlass = true
            bar.content.addSubview(button); toolButtons.append(button)
        }
        toolButtons.sort { $0.tag < $1.tag }
        return bar
    }
    @objc private func toolbarClicked(_ sender: NSButton) {
        commitText(); window?.makeFirstResponder(self)
        switch sender.tag {
        case 0...2, 7, 8:
            if textSelection == nil, tool == Self.annotationTools[sender.tag] {
                tool = nil
                for button in toolButtons.filter({ Self.annotationTools[$0.tag] != nil }) { button.state = .off }
                if editsWholeImage { beginTextSelection() }
                window?.invalidateCursorRects(for: self)
                return
            }
            endTextSelection()
            tool = Self.annotationTools[sender.tag]
            for button in toolButtons.filter({ Self.annotationTools[$0.tag] != nil }) { button.state = button.tag == sender.tag ? .on : .off }
            window?.invalidateCursorRects(for: self)
        case 3: undoAnnotation()
        case 4: onComplete?(nil)
        case 5: complete()
        case 6: toggleTextSelection()
        default: break
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if editing && !editsWholeImage && SelectionGeometry.handle(at: local, on: selection) != nil,
           !(toolbar?.frame.contains(local) ?? false) { return self }
        return super.hitTest(point)
    }
    private func toggleTextSelection() {
        if textSelection != nil { endTextSelection(); return }
        beginTextSelection()
    }
    private func beginTextSelection() {
        guard textSelection == nil, let crop = AnnotationRenderer.render(image: image, selection: selection, logicalSize: bounds.size, annotations: annotations) else { return }
        let layer = ImageTextSelection(image: crop, frame: selection, quiet: editsWholeImage, cached: cachedAnalysis)
        layer.onAnalysis = { [weak self] in self?.cachedAnalysis = $0 }
        layer.onCancel = { [weak self] in
            guard let self else { return }
            if self.editsWholeImage { self.onComplete?(nil) }
            else { self.endTextSelection(); self.window?.makeFirstResponder(self) }
        }
        layer.onConfirm = { [weak self] in self?.complete() }
        layer.onUndo = { [weak self] in self?.undoAnnotation() }
        textSelection = layer
        addSubview(layer, positioned: .below, relativeTo: toolbar)
        for button in toolButtons { if Self.annotationTools[button.tag] != nil || button.tag == 6 { button.state = button.tag == 6 ? .on : .off } }
        if !editsWholeImage {
            toolButtons.first { $0.tag == 5 }?.toolTip = "复制文字（未选中时复制全部）"
            toolButtons.first { $0.tag == 5 }?.setAccessibilityLabel("复制文字")
        }
        window?.invalidateCursorRects(for: self)
    }
    private func endTextSelection() {
        textSelection?.stop(); textSelection?.removeFromSuperview(); textSelection = nil
        for button in toolButtons {
            if let kind = Self.annotationTools[button.tag] { button.state = kind == tool ? .on : .off }
            if button.tag == 6 { button.state = .off }
            if button.tag == 5 {
                button.toolTip = editsWholeImage ? "复制图片" : "复制截图"
                button.setAccessibilityLabel(button.toolTip)
            }
        }
        window?.invalidateCursorRects(for: self)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if editsWholeImage, window != nil { beginTextSelection() }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { endTextSelection() }
        super.viewWillMove(toWindow: newWindow)
    }
    private func beginText(at point: CGPoint) {
        textOrigin = point
        let field = NSTextField(frame: NSRect(x: point.x, y: point.y, width: min(320, selection.maxX-point.x), height: min(30, selection.maxY-point.y)))
        guard field.frame.width >= 30, field.frame.height >= 20 else { return }
        field.font = .systemFont(ofSize: 20, weight: .semibold); field.textColor = .systemRed
        field.backgroundColor = Paperlight.raised
        field.focusRingType = .none; field.delegate = self; field.placeholderString = "文字"
        addSubview(field); textField = field; window?.makeFirstResponder(field)
    }
    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue
        if !text.isEmpty { cachedAnalysis = nil; annotations.append(Annotation(kind: .text, start: textOrigin, end: textOrigin, text: text)) }
        field.removeFromSuperview(); needsDisplay = true
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitText(); window?.makeFirstResponder(self); return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            textField?.removeFromSuperview(); textField = nil; window?.makeFirstResponder(self); return true
        }
        return false
    }
    private func undoAnnotation() {
        cachedAnalysis = nil
        let restoreSelection = editsWholeImage && textSelection != nil
        endTextSelection(); commitText()
        if !annotations.isEmpty { annotations.removeLast(); needsDisplay = true }
        if restoreSelection { beginTextSelection() }
    }
    private func complete() {
        if let textSelection {
            if !editsWholeImage || !textSelection.overlay.selectedText.isEmpty {
                textSelection.copyText(allIfUnselected: !editsWholeImage); return
            }
        }
        commitText()
        guard let rendered = AnnotationRenderer.render(image: image, selection: selection, logicalSize: bounds.size, annotations: annotations) else { NSSound.beep(); return }
        onComplete?(rendered)
    }
    override func rightMouseDown(with event: NSEvent) { onComplete?(nil) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            if editsWholeImage && textSelection == nil { commitText(); beginTextSelection() }
            else if !editsWholeImage && textSelection != nil { endTextSelection() }
            else { onComplete?(nil) }
        }
        else if let textSelection, event.modifierFlags.contains(.command), event.keyCode == 8 { textSelection.copyText(allIfUnselected: false) }
        else if editing && (event.keyCode == 36 || event.keyCode == 76) { complete() }
        else if editing && event.modifierFlags.contains(.command) && event.keyCode == 6 { undoAnnotation() }
        else { super.keyDown(with: event) }
    }
}

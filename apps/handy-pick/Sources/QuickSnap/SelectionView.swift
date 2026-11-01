import AppKit
import QuickSnapCore

final class SelectionView: NSView, NSTextFieldDelegate {
    let image: CGImage
    var onComplete: ((CGImage?) -> Void)?
    private var start: CGPoint?
    private var selection: CGRect = .zero
    private var editing = false
    private var tool: Annotation.Kind = .line
    private var annotations: [Annotation] = []
    private var draft: Annotation?
    private var toolbar: NSVisualEffectView?
    private var toolButtons: [NSButton] = []
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(image: CGImage) { self.image = image; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        if let toolbar { addCursorRect(toolbar.frame, cursor: .arrow) }
    }
    override func draw(_ dirtyRect: NSRect) {
        let picture = NSImage(cgImage: image, size: bounds.size)
        picture.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.black.withAlphaComponent(0.32).setFill(); bounds.fill()
        if selection.width > 0, selection.height > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            picture.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            annotations.forEach { $0.draw() }; draft?.draw()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: selection); outline.lineWidth = 1; outline.stroke()
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
            guard selection.contains(point) else { return }
            if tool == .text { beginText(at: point); return }
            start = point; draft = Annotation(kind: tool, start: point, end: point)
        } else { start = point; selection = .zero }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        if editing { draft?.end = clamped(point) }
        else { selection = SelectionGeometry.selection(from: start, to: point, in: bounds) }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        self.start = nil
        if editing {
            if var draft {
                draft.end = clamped(convert(event.locationInWindow, from: nil))
                if hypot(draft.end.x-draft.start.x, draft.end.y-draft.start.y) >= 2 { annotations.append(draft) }
            }
            draft = nil; needsDisplay = true; return
        }
        selection = SelectionGeometry.selection(from: start, to: convert(event.locationInWindow, from: nil), in: bounds)
        guard SelectionGeometry.pixels(for: selection, logicalSize: bounds.size, pixelSize: CGSize(width: image.width, height: image.height)) != nil else {
            selection = .zero; needsDisplay = true; return
        }
        editing = true; showToolbar(); needsDisplay = true
    }
    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, selection.minX), selection.maxX), y: min(max(point.y, selection.minY), selection.maxY))
    }
    private func showToolbar() {
        let width: CGFloat = 280, height: CGFloat = 44
        var y = selection.maxY + 10
        if y + height > bounds.maxY - 8 { y = selection.minY - height - 10 }
        y = min(max(8, y), bounds.maxY-height-8)
        let x = min(max(8, selection.maxX-width), bounds.maxX-width-8)
        let bar = NSVisualEffectView(frame: NSRect(x: x, y: y, width: width, height: height))
        bar.material = .hudWindow; bar.blendingMode = .withinWindow; bar.state = .active
        bar.wantsLayer = true; bar.layer?.cornerRadius = 12; bar.layer?.masksToBounds = true
        let symbols = ["line.diagonal", "circle", "textformat", "arrow.uturn.backward", "xmark", "checkmark"]
        let labels = ["划线", "画圈", "文字", "撤销", "取消", "复制截图"]
        for index in symbols.indices {
            let button = NSButton(image: NSImage(systemSymbolName: symbols[index], accessibilityDescription: labels[index])!, target: self, action: #selector(toolbarClicked(_:)))
            button.frame = NSRect(x: 8 + CGFloat(index)*44, y: 7, width: 40, height: 30)
            button.tag = index; button.bezelStyle = .texturedRounded; button.toolTip = labels[index]
            button.setAccessibilityLabel(labels[index]); button.setButtonType(index < 3 ? .toggle : .momentaryPushIn)
            button.contentTintColor = index == 5 ? .systemGreen : .labelColor
            bar.addSubview(button); toolButtons.append(button)
        }
        toolButtons[0].state = .on
        addSubview(bar); toolbar = bar; window?.invalidateCursorRects(for: self)
    }
    @objc private func toolbarClicked(_ sender: NSButton) {
        commitText(); window?.makeFirstResponder(self)
        switch sender.tag {
        case 0...2:
            tool = [.line, .ellipse, .text][sender.tag]
            for button in toolButtons.prefix(3) { button.state = button.tag == sender.tag ? .on : .off }
        case 3: undoAnnotation()
        case 4: onComplete?(nil)
        case 5: complete()
        default: break
        }
    }
    private func beginText(at point: CGPoint) {
        textOrigin = point
        let field = NSTextField(frame: NSRect(x: point.x, y: point.y, width: min(320, selection.maxX-point.x), height: min(30, selection.maxY-point.y)))
        guard field.frame.width >= 30, field.frame.height >= 20 else { return }
        field.font = .systemFont(ofSize: 20, weight: .semibold); field.textColor = .systemRed
        field.backgroundColor = .textBackgroundColor.withAlphaComponent(0.9)
        field.focusRingType = .none; field.delegate = self; field.placeholderString = "文字"
        addSubview(field); textField = field; window?.makeFirstResponder(field)
    }
    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue
        if !text.isEmpty { annotations.append(Annotation(kind: .text, start: textOrigin, end: textOrigin, text: text)) }
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
    private func undoAnnotation() { if !annotations.isEmpty { annotations.removeLast(); needsDisplay = true } }
    private func complete() {
        commitText()
        guard let rendered = AnnotationRenderer.render(image: image, selection: selection, logicalSize: bounds.size, annotations: annotations) else { NSSound.beep(); return }
        onComplete?(rendered)
    }
    override func rightMouseDown(with event: NSEvent) { onComplete?(nil) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onComplete?(nil) }
        else if editing && (event.keyCode == 36 || event.keyCode == 76) { complete() }
        else if editing && event.modifierFlags.contains(.command) && event.keyCode == 6 { commitText(); undoAnnotation() }
        else { super.keyDown(with: event) }
    }
}

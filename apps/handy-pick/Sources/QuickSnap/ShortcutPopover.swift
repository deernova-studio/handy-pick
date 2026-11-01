import AppKit
import ImageIO
import QuickSnapCore

final class ShortcutPopover: NSViewController {
    var onRecord: (() -> Void)?
    var onPermission: (() -> Void)?
    var onSelect: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onClear: (() -> Void)?
    var onSizeChange: ((NSSize) -> Void)?
    private let scroll = NSScrollView()
    private let separator = PaperlightSurface()
    private let bindingButton = PaperlightButton(title: "", target: nil, action: nil)
    private let grid = FlippedHistoryView()
    private var needsPermission = false

    override func loadView() {
        let root = PaperlightSurface(frame: NSRect(x: 0, y: 0, width: 400, height: 392))
        let caption = NSTextField(labelWithString: "设置")
        caption.frame = NSRect(x: 16, y: 18, width: 50, height: 18)
        caption.font = Paperlight.label; caption.textColor = Paperlight.ink
        root.addSubview(caption)
        bindingButton.frame = NSRect(x: 184, y: 16, width: 200, height: 24)
        bindingButton.target = self; bindingButton.action = #selector(record)
        bindingButton.font = Paperlight.label
        bindingButton.style = .secondary; bindingButton.isBordered = false
        bindingButton.bezelStyle = .rounded
        bindingButton.setAccessibilityLabel("设置双击快捷键")
        bindingButton.toolTip = "点击后按新键，Esc 取消"
        root.addSubview(bindingButton)
        separator.frame = NSRect(x: 16, y: 55, width: 368, height: Paperlight.hairline(root))
        separator.fill = Paperlight.line; root.addSubview(separator)
        scroll.frame = NSRect(x: 16, y: 64, width: 368, height: 312)
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = grid; root.addSubview(scroll)
        let menu = NSMenu()
        let clear = NSMenuItem(title: "清空记录", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self; menu.addItem(clear); root.menu = menu; grid.menu = menu
        view = root; preferredContentSize = root.frame.size
        updateHistory([])
    }

    func update(binding: String, recording: Bool, needsPermission: Bool) {
        loadViewIfNeeded(); self.needsPermission = needsPermission
        bindingButton.title = needsPermission ? "授权…" : (recording ? "请按新键…" : "双击 · \(binding)")
    }
    func updateHistory(_ entries: [ClipboardHistory.Entry]) {
        loadViewIfNeeded()
        grid.subviews.forEach { $0.removeFromSuperview() }
        grid.frame = NSRect(x: 0, y: 0, width: 368, height: max(312, CGFloat((entries.count + 2) / 3) * 120))
        scroll.isHidden = entries.isEmpty
        separator.isHidden = entries.isEmpty
        let size = NSSize(width: 400, height: entries.isEmpty ? 56 : 392)
        if preferredContentSize != size {
            preferredContentSize = size
            onSizeChange?(size)
            view.setFrameSize(size)
        }
        for (index, entry) in entries.enumerated() {
            let tile = HistoryTile(entry: entry)
            let width: CGFloat = 117.333333
            tile.frame = NSRect(x: CGFloat(index % 3) * (width + 8), y: CGFloat(index / 3) * 120, width: width, height: 112)
            tile.onSelect = { [weak self] in self?.onSelect?(entry.id) }
            tile.onRemove = { [weak self] in self?.onRemove?(entry.id) }
            tile.onClear = { [weak self] in self?.onClear?() }
            grid.addSubview(tile)
        }
    }
    @objc private func clearHistory() { onClear?() }
    @objc private func record() { if needsPermission { onPermission?() } else { onRecord?() } }
}

private final class FlippedHistoryView: NSView { override var isFlipped: Bool { true } }

private final class HistoryTile: PaperlightButton {
    var onSelect: (() -> Void)?
    var onRemove: (() -> Void)?
    var onClear: (() -> Void)?
    private let entry: ClipboardHistory.Entry
    private var preview: NSImage?
    init(entry: ClipboardHistory.Entry) {
        self.entry = entry; super.init(frame: .zero)
        isBordered = false; focusRingType = .none; title = ""; target = self; action = #selector(choose)
        if case .image(let data, _) = entry.content {
            // Downsample for thumbnails without keeping a full decoded image per tile.
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                 kCGImageSourceCreateThumbnailFromImageAlways: true,
                 kCGImageSourceThumbnailMaxPixelSize: 240,
                 kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
                preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
            setAccessibilityLabel("复制图片")
        } else { setAccessibilityLabel("复制文字记录") }
        let menu = NSMenu()
        for (title, selector) in [("删除这条", #selector(removeEntry)), ("清空记录", #selector(clearEntries))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        self.menu = menu
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        Paperlight.surface.setFill(); card.fill()
        if isHighlighted { Paperlight.selected.setFill(); card.fill() }
        (isHighlighted ? Paperlight.ink : (hovered ? Paperlight.controlLine : Paperlight.line)).setStroke()
        card.lineWidth = isHighlighted ? 1 : Paperlight.hairline(self); card.stroke()
        if window?.firstResponder === self { Paperlight.ink.setStroke(); card.lineWidth = 2; card.stroke() }
        let contentRect = NSRect(x: 12, y: 32, width: bounds.width-24, height: bounds.height-44)
        let metadata: String
        if case .image = entry.content {
            metadata = "图片"
            if let preview {
                let scale = min(contentRect.width / preview.size.width, contentRect.height / preview.size.height)
                let size = NSSize(width: preview.size.width * scale, height: preview.size.height * scale)
                preview.draw(in: NSRect(x: contentRect.midX-size.width/2, y: contentRect.midY-size.height/2, width: size.width, height: size.height))
            }
        } else if case .text(let text) = entry.content {
            metadata = "文字"
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
            paragraph.minimumLineHeight = 18; paragraph.maximumLineHeight = 18
            (String(text.prefix(300)) as NSString).draw(with: contentRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: [
                .font: Paperlight.body, .foregroundColor: Paperlight.ink, .paragraphStyle: paragraph])
        } else { metadata = "" }
        (metadata as NSString).draw(at: NSPoint(x: 12, y: 12), withAttributes: [
            .font: Paperlight.caption, .foregroundColor: Paperlight.tertiary])
    }

    @objc private func choose() { onSelect?() }
    @objc private func removeEntry() { onRemove?() }
    @objc private func clearEntries() { onClear?() }
}

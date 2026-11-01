import AppKit
import ImageIO
import QuickSnapCore

final class ShortcutPopover: NSViewController {
    var onRecord: (() -> Void)?
    var onPermission: (() -> Void)?
    var onSelect: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onClear: (() -> Void)?
    private let bindingButton = NSButton(title: "", target: nil, action: nil)
    private let grid = FlippedHistoryView()
    private var needsPermission = false

    override func loadView() {
        let root = FlippedHistoryView(frame: NSRect(x: 0, y: 0, width: 360, height: 354))
        let caption = NSTextField(labelWithString: "设置")
        caption.frame = NSRect(x: 16, y: 19, width: 50, height: 18)
        caption.font = .systemFont(ofSize: 13, weight: .medium)
        root.addSubview(caption)
        bindingButton.frame = NSRect(x: 125, y: 12, width: 219, height: 30)
        bindingButton.target = self; bindingButton.action = #selector(record)
        bindingButton.font = .systemFont(ofSize: 12)
        bindingButton.bezelStyle = .rounded
        bindingButton.setAccessibilityLabel("设置双击快捷键")
        bindingButton.toolTip = "点击后按新键，Esc 取消"
        root.addSubview(bindingButton)
        let separator = NSBox(frame: NSRect(x: 12, y: 54, width: 336, height: 1))
        separator.boxType = .separator; root.addSubview(separator)
        let scroll = NSScrollView(frame: NSRect(x: 8, y: 64, width: 344, height: 282))
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
        grid.frame = NSRect(x: 0, y: 0, width: 328, height: max(276, CGFloat((entries.count + 2) / 3) * 102))
        if entries.isEmpty {
            let empty = NSTextField(labelWithString: "暂无记录")
            empty.textColor = .tertiaryLabelColor; empty.font = .systemFont(ofSize: 13)
            empty.alignment = .center; empty.frame = NSRect(x: 0, y: 112, width: 328, height: 24)
            grid.addSubview(empty)
        }
        for (index, entry) in entries.enumerated() {
            let tile = HistoryTile(entry: entry)
            tile.frame = NSRect(x: CGFloat(index % 3) * 110 + 2, y: CGFloat(index / 3) * 102 + 2, width: 104, height: 94)
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

private final class HistoryTile: NSButton {
    var onSelect: (() -> Void)?
    var onRemove: (() -> Void)?
    var onClear: (() -> Void)?
    private let entry: ClipboardHistory.Entry
    private var preview: NSImage?
    init(entry: ClipboardHistory.Entry) {
        self.entry = entry; super.init(frame: .zero)
        isBordered = false; title = ""; target = self; action = #selector(choose)
        if case .image(let data, _) = entry.content {
            // Downsample for thumbnails without keeping a full decoded image per tile.
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                 kCGImageSourceCreateThumbnailFromImageAlways: true,
                 kCGImageSourceThumbnailMaxPixelSize: 208,
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
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
        (isHighlighted ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.controlBackgroundColor.withAlphaComponent(0.65)).setFill(); card.fill()
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke(); card.lineWidth = 0.5; card.stroke()
        let inset = bounds.insetBy(dx: 10, dy: 10)
        if let preview {
            let scale = min(inset.width / preview.size.width, inset.height / preview.size.height)
            let size = NSSize(width: preview.size.width * scale, height: preview.size.height * scale)
            preview.draw(in: NSRect(x: bounds.midX-size.width/2, y: bounds.midY-size.height/2, width: size.width, height: size.height))
        } else if case .text(let text) = entry.content {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
            (String(text.prefix(300)) as NSString).draw(with: inset, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
        }
    }
    @objc private func choose() { onSelect?() }
    @objc private func removeEntry() { onRemove?() }
    @objc private func clearEntries() { onClear?() }
}

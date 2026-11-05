import AppKit
import ImageIO
import QuickSnapCore

final class ShortcutPopover: NSViewController {
    var onRecord: (() -> Void)?
    var onPermission: (() -> Void)?
    var onSelect: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onClear: (() -> Void)?
    var onPreview: ((UUID) -> Void)?
    var onModeChange: ((ShortcutMode) -> Void)?
    var onSizeChange: ((NSSize) -> Void)?
    private let typeFilter = NSSegmentedControl()
    private let filterDivider = PaperlightSurface()
    private var history: [ClipboardHistory.Entry] = []
    private var selectedType = 0
    private let scroll = NSScrollView()
    private let separator = PaperlightSurface()
    private let bindingButton = NSButton(title: "", target: nil, action: nil)
    private let modeButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let grid = FlippedHistoryView()
    private var needsPermission = false

    override func loadView() {
        let root = PaperlightSurface(frame: NSRect(x: 0, y: 0, width: 360, height: 392))
        modeButton.frame = NSRect(x: 12, y: 14, width: 88, height: 28)
        // A pop-up aligns its selected row over the control. A pull-down opens
        // below it; its hidden first item supplies the current mode's title.
        modeButton.addItems(withTitles: ["触发方式", "双击", "组合键"])
        modeButton.item(at: 0)?.isHidden = true
        modeButton.preferredEdge = .minY
        modeButton.font = Paperlight.label
        modeButton.target = self; modeButton.action = #selector(selectTriggerMode)
        modeButton.setAccessibilityLabel("触发方式")
        root.addSubview(modeButton)
        bindingButton.frame = NSRect(x: 184, y: 16, width: 160, height: 24)
        bindingButton.target = self; bindingButton.action = #selector(record)
        bindingButton.font = Paperlight.label
        bindingButton.controlSize = .regular; bindingButton.isBordered = true
        bindingButton.bezelStyle = .rounded
        bindingButton.setAccessibilityLabel("录入快捷键")
        bindingButton.toolTip = "点击后按新键，Esc 取消"
        root.addSubview(bindingButton)
        separator.frame = NSRect(x: 16, y: 55, width: 328, height: Paperlight.hairline(root))
        separator.fill = Paperlight.line; root.addSubview(separator)
        scroll.frame = NSRect(x: 16, y: 64, width: 328, height: 312)
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = grid; root.addSubview(scroll)
        typeFilter.frame = NSRect(x: 240, y: 16, width: 104, height: 24)
        filterDivider.frame = NSRect(x: 232, y: 18, width: Paperlight.hairline(root), height: 20)
        filterDivider.fill = Paperlight.line; root.addSubview(filterDivider)
        typeFilter.identifier = NSUserInterfaceItemIdentifier("historyTypeFilter")
        typeFilter.segmentCount = 3; typeFilter.trackingMode = .selectOne
        typeFilter.segmentStyle = .rounded; typeFilter.controlSize = .regular
        typeFilter.target = self; typeFilter.action = #selector(selectHistoryType(_:))
        typeFilter.setAccessibilityLabel("剪贴板类型")
        for (index, item) in [("square.grid.2x2", "全部"), ("photo", "图片"), ("text.alignleft", "文字")].enumerated() {
            let image = NSImage(systemSymbolName: item.0, accessibilityDescription: item.1)!
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))!
            typeFilter.setImage(image, forSegment: index)
            typeFilter.setImageScaling(.scaleProportionallyDown, forSegment: index)
            typeFilter.setWidth(28, forSegment: index)
            typeFilter.setToolTip(item.1, forSegment: index)
        }
        root.addSubview(typeFilter)
        let menu = NSMenu()
        let clear = NSMenuItem(title: "清空记录", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self; menu.addItem(clear); root.menu = menu; grid.menu = menu
        view = root; preferredContentSize = root.frame.size
        updateHistory([])
    }

    func update(binding: String, recording: Bool, needsPermission: Bool, mode: ShortcutMode = .doublePress) {
        loadViewIfNeeded(); self.needsPermission = needsPermission
        modeButton.item(at: 0)?.title = mode == .doublePress ? "双击" : "组合键"
        modeButton.selectItem(at: mode == .doublePress ? 1 : 2)
        modeButton.item(at: 1)?.state = mode == .doublePress ? .on : .off
        modeButton.item(at: 2)?.state = mode == .chord ? .on : .off
        bindingButton.title = needsPermission ? "授权…" : (recording ? (mode == .chord ? "请按组合键…" : "请按新键…") : binding)
        bindingButton.toolTip = mode == .chord ? "按住 ⌘、⌃、⌥ 或 ⇧ 再按一个键；一次触发，输入框内也生效；Esc 取消" : "点击后按新键，双击触发；Esc 取消"
    }
    func updateHistory(_ entries: [ClipboardHistory.Entry]) {
        loadViewIfNeeded()
        history = entries
        let imageCount = entries.filter { if case .image = $0.content { return true }; return false }.count
        let counts = [entries.count, imageCount, entries.count-imageCount]
        if counts[selectedType] == 0 { selectedType = 0 }
        for index in 0..<3 { typeFilter.setEnabled(counts[index] > 0, forSegment: index) }
        renderHistory()
    }
    @objc private func selectHistoryType(_ sender: NSSegmentedControl) {
        selectedType = sender.selectedSegment
        scroll.contentView.scroll(to: .zero)
        renderHistory()
    }
    private func renderHistory() {
        typeFilter.selectedSegment = selectedType
        let entries = history.filter {
            switch $0.content {
            case .image: return selectedType != 2
            case .text: return selectedType != 1
            }
        }
        grid.subviews.forEach { $0.removeFromSuperview() }
        let rows = (entries.count + 2) / 3
        let contentHeight = max(0, CGFloat(rows) * 120 - 8)
        let visibleHeight = max(0, CGFloat(min(rows, 3)) * 120 - 8)
        let previousOrigin = scroll.contentView.bounds.origin
        scroll.frame = NSRect(x: 16, y: 64, width: 328, height: visibleHeight)
        grid.frame = NSRect(x: 0, y: 0, width: 328, height: contentHeight)
        scroll.hasVerticalScroller = rows > 3
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, previousOrigin.y), max(0, contentHeight-visibleHeight))))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroll.isHidden = entries.isEmpty
        separator.isHidden = entries.isEmpty
        typeFilter.isHidden = history.isEmpty
        filterDivider.isHidden = history.isEmpty
        let size = NSSize(width: entries.isEmpty ? 240 : 360, height: entries.isEmpty ? 56 : 64 + visibleHeight + 16)
        // AppKit bezel/shadow insets differ by control type and OS version.
        // Align visible control rectangles instead of assigning equal outer frames.
        modeButton.frame = modeButton.frame(forAlignmentRect: NSRect(x: 16, y: 16, width: 80, height: 24))
        bindingButton.frame = bindingButton.frame(forAlignmentRect: NSRect(x: 104, y: 16, width: 120, height: 24))
        typeFilter.frame = typeFilter.frame(forAlignmentRect: NSRect(x: 240, y: 16, width: 104, height: 24))
        if preferredContentSize != size {
            preferredContentSize = size
            onSizeChange?(size)
            view.setFrameSize(size)
        }
        for (index, entry) in entries.enumerated() {
            let tile = HistoryTile(entry: entry)
            let width: CGFloat = 104
            tile.frame = NSRect(x: CGFloat(index % 3) * (width + 8), y: CGFloat(index / 3) * 120, width: width, height: 112)
            tile.onSelect = { [weak self] in self?.onSelect?(entry.id) }
            tile.onRemove = { [weak self] in self?.onRemove?(entry.id) }
            tile.onClear = { [weak self] in self?.onClear?() }
            tile.onPreview = { [weak self] in self?.onPreview?(entry.id) }
            grid.addSubview(tile)
        }
    }
    func showRecordingHint(_ text: String) { bindingButton.title = text }
    @objc private func clearHistory() { onClear?() }
    @objc private func record() { if needsPermission { onPermission?() } else { onRecord?() } }
    @objc private func selectTriggerMode() { onModeChange?(modeButton.indexOfSelectedItem == 2 ? .chord : .doublePress) }
}

private final class FlippedHistoryView: NSView { override var isFlipped: Bool { true } }

final class HistoryTile: PaperlightButton {
    var onSelect: (() -> Void)?
    var onRemove: (() -> Void)?
    var onClear: (() -> Void)?
    var onPreview: (() -> Void)?
    private let expandButton = PaperlightButton(title: "", target: nil, action: nil)
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
        expandButton.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "放大预览")
        expandButton.setAccessibilityLabel("放大预览")
        expandButton.toolTip = "放大预览"
        expandButton.style = .secondary; expandButton.isBordered = false
        expandButton.target = self; expandButton.action = #selector(expand)
        expandButton.isHidden = true
        addSubview(expandButton)
        let menu = NSMenu()
        for (title, selector) in [("放大预览", #selector(expand)), ("删除这条", #selector(removeEntry)), ("清空记录", #selector(clearEntries))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        self.menu = menu
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    override func layout() {
        super.layout()
        expandButton.frame = NSRect(x: bounds.width-32, y: isFlipped ? 6 : bounds.height-32, width: 26, height: 26)
    }
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event); expandButton.isHidden = false
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event); expandButton.isHidden = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        Paperlight.surface.setFill(); card.fill()
        if isHighlighted { Paperlight.selected.setFill(); card.fill() }
        (isHighlighted ? Paperlight.ink : (hovered ? Paperlight.controlLine : Paperlight.line)).setStroke()
        card.lineWidth = isHighlighted ? 1 : Paperlight.hairline(self); card.stroke()
        if window?.firstResponder === self { Paperlight.ink.setStroke(); card.lineWidth = 2; card.stroke() }
        let contentRect = bounds.insetBy(dx: 12, dy: 12)
        if case .image = entry.content {
            if let preview {
                let scale = min(contentRect.width / preview.size.width, contentRect.height / preview.size.height)
                let size = NSSize(width: preview.size.width * scale, height: preview.size.height * scale)
                preview.draw(in: NSRect(x: contentRect.midX-size.width/2, y: contentRect.midY-size.height/2, width: size.width, height: size.height))
            }
        } else if case .text(let text) = entry.content {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
            paragraph.minimumLineHeight = 18; paragraph.maximumLineHeight = 18
            (String(text.prefix(300)) as NSString).draw(with: contentRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: [
                .font: Paperlight.body, .foregroundColor: Paperlight.ink, .paragraphStyle: paragraph])
        }
    }

    @objc private func choose() { onSelect?() }
    @objc private func expand() { onPreview?() }
    @objc private func removeEntry() { onRemove?() }
    @objc private func clearEntries() { onClear?() }
}

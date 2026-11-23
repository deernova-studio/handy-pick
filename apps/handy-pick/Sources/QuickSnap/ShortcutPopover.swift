import AppKit
import ImageIO
import QuickSnapCore

final class ShortcutPopover: NSViewController {
    var onRecord: ((ShortcutAction) -> Void)?
    var onPermission: (() -> Void)?
    var onSelect: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onClear: (() -> Void)?
    var onPreview: ((UUID) -> Void)?
    var onModeChange: ((ShortcutMode) -> Void)?
    var onSizeChange: ((NSSize) -> Void)?
    var onSettingsCollapsed: (() -> Void)?
    private let historyLabel = NSTextField(labelWithString: "剪贴板")
    private let typeFilter = NSSegmentedControl()
    private let settingsButton = PaperlightButton(title: "", target: nil, action: nil)
    private let settings = PaperlightSurface()
    private var settingsExpanded = false
    private var availableHeight: CGFloat = .infinity
    private let headerHeight: CGFloat = 48
    private let settingsHeight: CGFloat = 152
    private var history: [ClipboardHistory.Entry] = []
    private var selectedType = 0
    private let scroll = NSScrollView()
    private var recordingAction: ShortcutAction?
    private let recordingButtons = ShortcutAction.allCases.map { _ in NSButton(title: "", target: nil, action: nil) }
    private let modeButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let grid = FlippedHistoryView()
    private var needsPermission = false

    override func loadView() {
        let root = PaperlightSurface(frame: NSRect(x: 0, y: 0, width: 360, height: headerHeight))
        historyLabel.font = Paperlight.label
        historyLabel.textColor = Paperlight.secondary
        historyLabel.frame = NSRect(x: 16, y: 16, width: 180, height: 20)
        root.addSubview(historyLabel)
        settingsButton.frame = NSRect(x: 320, y: 12, width: 24, height: 24)
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "快捷键设置")
        settingsButton.setButtonType(.pushOnPushOff)
        settingsButton.setAccessibilityLabel("快捷键设置")
        settingsButton.toolTip = "展开快捷键设置"
        settingsButton.isBordered = false
        settingsButton.target = self; settingsButton.action = #selector(toggleSettings)
        root.addSubview(settingsButton)
        settings.isHidden = true
        root.addSubview(settings)
        let divider = PaperlightSurface(frame: NSRect(x: 16, y: 0, width: 328, height: Paperlight.hairline(root)))
        divider.fill = Paperlight.line
        settings.addSubview(divider)
        let modeLabel = NSTextField(labelWithString: "触发方式")
        modeLabel.font = Paperlight.body
        modeLabel.textColor = Paperlight.secondary
        modeLabel.frame = NSRect(x: 16, y: 13, width: 116, height: 24)
        settings.addSubview(modeLabel)
        // A pop-up aligns its selected row over the control. A pull-down opens
        // below it; its hidden first item supplies the current mode's title.
        modeButton.addItems(withTitles: ["触发方式", "双击", "组合键"])
        modeButton.item(at: 0)?.isHidden = true
        modeButton.preferredEdge = .minY
        modeButton.font = Paperlight.label
        modeButton.target = self; modeButton.action = #selector(selectTriggerMode)
        modeButton.setAccessibilityLabel("触发方式")
        modeButton.frame = modeButton.frame(forAlignmentRect: NSRect(x: 144, y: 12, width: 200, height: 24))
        settings.addSubview(modeButton)
        for action in ShortcutAction.allCases {
            let y = 46 + CGFloat(action.rawValue) * 32
            let label = NSTextField(labelWithString: action.title)
            label.font = Paperlight.body
            label.textColor = Paperlight.secondary
            label.frame = NSRect(x: 16, y: y + 1, width: 116, height: 24)
            settings.addSubview(label)

            let button = recordingButtons[action.rawValue]
            button.target = self
            button.action = #selector(record(_:))
            button.tag = action.rawValue
            button.font = Paperlight.label
            button.controlSize = .regular
            button.isBordered = true
            button.bezelStyle = .rounded
            button.frame = button.frame(forAlignmentRect: NSRect(x: 144, y: y, width: 200, height: 24))
            button.setAccessibilityLabel("录入\(action.title)快捷键")
            settings.addSubview(button)
        }
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = grid; root.addSubview(scroll)
        typeFilter.identifier = NSUserInterfaceItemIdentifier("historyTypeFilter")
        typeFilter.segmentCount = 3; typeFilter.trackingMode = .selectOne
        typeFilter.segmentStyle = .rounded; typeFilter.controlSize = .regular
        typeFilter.target = self; typeFilter.action = #selector(selectHistoryType(_:))
        typeFilter.setAccessibilityLabel("剪贴板类型")
        for (index, item) in [("square.grid.2x2", "全部"), ("photo", "图片"), ("text.alignleft", "文字")].enumerated() {
            let image = Self.filterIcon(item.0, description: item.1)
            typeFilter.setImage(image, forSegment: index)
            typeFilter.setImageScaling(.scaleNone, forSegment: index)
            typeFilter.setWidth(28, forSegment: index)
            typeFilter.setToolTip(item.1, forSegment: index)
        }
        typeFilter.frame = typeFilter.frame(forAlignmentRect: NSRect(x: 208, y: 12, width: 104, height: 24))
        root.addSubview(typeFilter)
        let menu = NSMenu()
        let clear = NSMenuItem(title: "清空记录", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self; menu.addItem(clear); root.menu = menu; grid.menu = menu
        view = root; preferredContentSize = root.frame.size
        updateHistory([])
    }

    @objc private func toggleSettings() { setSettingsExpanded(!settingsExpanded) }

    func setSettingsExpanded(_ expanded: Bool) {
        loadViewIfNeeded()
        guard settingsExpanded != expanded else { return }
        settingsExpanded = expanded
        settingsButton.state = expanded ? .on : .off
        settingsButton.toolTip = expanded ? "收起快捷键设置" : "展开快捷键设置"
        if !expanded, let responder = view.window?.firstResponder as? NSView, responder.isDescendant(of: settings) {
            view.window?.makeFirstResponder(settingsButton)
        }
        layoutSections()
        if !expanded { onSettingsCollapsed?() }
    }

    func limitHeight(to height: CGFloat) {
        availableHeight = height
        layoutSections()
    }

    /// Freeze the symbol's geometry: the native segment still supplies its
    /// selected background/tint, but cannot substitute a larger/heavier symbol.
    private static func filterIcon(_ name: String, description: String) -> NSImage {
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: description)!
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))!
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        let ratio = min(1, 14 / max(symbol.size.width, symbol.size.height))
        let glyph = NSSize(width: symbol.size.width * ratio, height: symbol.size.height * ratio)
        for scale in [1, 2, 3] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: 16 * scale, pixelsHigh: 16 * scale,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            symbol.draw(in: NSRect(x: (16-glyph.width)/2, y: (16-glyph.height)/2,
                                  width: glyph.width, height: glyph.height))
            NSGraphicsContext.restoreGraphicsState()
            bitmap.size = size; image.addRepresentation(bitmap)
        }
        image.isTemplate = true; image.accessibilityDescription = description
        return image
    }

    func update(bindings: [ShortcutAction: ShortcutBinding], recording: ShortcutAction?, needsPermission: Bool, mode: ShortcutMode) {
        loadViewIfNeeded()
        self.needsPermission = needsPermission
        recordingAction = recording
        let prompt = mode == .chord ? "请按组合键…" : "请按新键…"
        let hint = mode == .chord ? "按住修饰键，再按主键。按 Esc 取消。" : "录入后双击触发。按 Esc 取消。"
        modeButton.item(at: 0)?.title = mode == .doublePress ? "双击" : "组合键"
        modeButton.selectItem(at: mode == .doublePress ? 1 : 2)
        modeButton.item(at: 1)?.state = mode == .doublePress ? .on : .off
        modeButton.item(at: 2)?.state = mode == .chord ? .on : .off
        for action in ShortcutAction.allCases {
            let button = recordingButtons[action.rawValue]
            button.title = needsPermission ? "授权…" : (recording == action ? prompt : bindings[action]?.displayName ?? "录入…")
            button.toolTip = hint
        }
    }
    func updateHistory(_ entries: [ClipboardHistory.Entry]) {
        loadViewIfNeeded()
        history = entries
        historyLabel.stringValue = entries.isEmpty ? "暂无剪贴板记录" : "剪贴板"
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
        grid.frame = NSRect(x: 0, y: 0, width: 328, height: contentHeight)
        typeFilter.isHidden = history.isEmpty
        layoutSections()
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

    private func layoutSections() {
        let contentHeight = grid.frame.height
        let settingsSpace = settingsExpanded ? settingsHeight : 0
        let spacing: CGFloat = contentHeight > 0 ? 12 : 0
        let viewport = min(contentHeight, 352, max(0, availableHeight - headerHeight - spacing - settingsSpace))
        let previousY = scroll.contentView.bounds.origin.y
        scroll.frame = NSRect(x: 16, y: headerHeight, width: 328, height: viewport)
        scroll.hasVerticalScroller = contentHeight > viewport
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(previousY, max(0, contentHeight - viewport))))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroll.isHidden = viewport == 0
        let historyBottom = headerHeight + viewport + spacing
        settings.frame = NSRect(x: 0, y: historyBottom, width: 360, height: settingsHeight)
        settings.isHidden = !settingsExpanded
        let size = NSSize(width: 360, height: historyBottom + settingsSpace)
        if preferredContentSize != size {
            preferredContentSize = size
            onSizeChange?(size)
            view.setFrameSize(size)
        }
    }
    func showRecordingHint(_ text: String) {
        if let action = recordingAction { recordingButtons[action.rawValue].title = text }
    }
    @objc private func clearHistory() { onClear?() }
    @objc private func record(_ sender: NSButton) {
        if needsPermission {
            onPermission?()
        } else if let action = ShortcutAction(rawValue: sender.tag) {
            onRecord?(action)
        }
    }
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

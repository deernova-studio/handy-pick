import AppKit
import QuickSnapCore

/// A session-only preview. Opening it never reads or writes the system clipboard.
final class HistoryPreview: NSObject, NSWindowDelegate {
    private(set) var entryID: UUID?
    private(set) var window: NSPanel?
    var onDismiss: (() -> Void)?

    func show(_ entry: ClipboardHistory.Entry) {
        dismiss()
        entryID = entry.id
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let size = NSSize(width: min(720, visible.width-48), height: min(520, visible.height-64))
        let panel = PreviewPanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "预览"; panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = Paperlight.canvas
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.minSize = NSSize(width: 320, height: 240)
        panel.delegate = self
        panel.contentView = Self.contentView(for: entry.content, size: size)
        panel.setFrameOrigin(NSPoint(x: visible.midX-panel.frame.width/2, y: visible.midY-panel.frame.height/2))
        window = panel
        panel.makeKeyAndOrderFront(nil)
    }

    static func contentView(for content: ClipboardHistory.Content, size: NSSize) -> NSView {
        let root = PaperlightSurface(frame: NSRect(origin: .zero, size: size))
        switch content {
        case .image(let data, _):
            let image = NSImageView(frame: root.bounds.insetBy(dx: 16, dy: 16))
            image.image = NSImage(data: data)
            image.imageScaling = .scaleProportionallyUpOrDown
            image.imageAlignment = .alignCenter
            image.autoresizingMask = [.width, .height]
            image.setAccessibilityLabel("剪贴板图片预览")
            root.addSubview(image)
        case .text(let string):
            let scroll = NSScrollView(frame: root.bounds.insetBy(dx: 16, dy: 16))
            scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            let text = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
            text.isEditable = false; text.isSelectable = true; text.isRichText = false
            text.drawsBackground = false; text.textColor = Paperlight.ink
            text.font = .systemFont(ofSize: 15)
            text.textContainerInset = NSSize(width: 8, height: 8)
            text.isVerticallyResizable = true; text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]
            text.minSize = NSSize(width: 0, height: scroll.contentSize.height)
            text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            text.textContainer?.widthTracksTextView = true
            text.string = string
            text.setAccessibilityLabel("剪贴板文字预览")
            scroll.documentView = text
            root.addSubview(scroll)
        }
        return root
    }

    func retainOnly(_ ids: Set<UUID>) {
        if let entryID, !ids.contains(entryID) { dismiss() }
    }

    func dismiss() {
        guard let panel = window else { return }
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil; entryID = nil
        onDismiss?()
    }
}

private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { close() }
}

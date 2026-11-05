import AppKit
import VisionKit

/// On-device Live Text over the exact crop displayed to the user.
@MainActor final class ImageTextSelection: NSImageView, ImageAnalysisOverlayViewDelegate {
    let overlay = ImageAnalysisOverlayView(frame: .zero)
    private let status = NSTextField(labelWithString: "正在识别文字…")
    private let analyzer = ImageAnalyzer()
    private var work: Task<Void, Never>?
    private let feedback = CopyFeedback()
    private(set) var recognitionFinished = false
    private(set) var recognizedText = ""
    var onConfirm: (() -> Void)?
    private let quiet: Bool
    var onCancel: (() -> Void)?

    init(image: CGImage, frame: NSRect, quiet: Bool = false) {
        self.quiet = quiet
        super.init(frame: frame)
        self.image = NSImage(cgImage: image, size: frame.size)
        imageScaling = .scaleAxesIndependently
        overlay.frame = bounds; overlay.autoresizingMask = [.width, .height]
        overlay.delegate = self; overlay.trackingImageView = self
        overlay.preferredInteractionTypes = .textSelection
        overlay.isSupplementaryInterfaceHidden = true
        addSubview(overlay)
        status.font = Paperlight.label; status.textColor = Paperlight.ink
        status.backgroundColor = Paperlight.raised; status.drawsBackground = true
        status.alignment = .center
        status.setAccessibilityLabel("文字识别状态")
        status.isHidden = quiet
        addSubview(status)
        guard ImageAnalyzer.isSupported else {
            status.stringValue = "此设备不支持文字识别"; recognitionFinished = true; return
        }
        work = Task { [weak self, analyzer] in
            do {
                let analysis = try await analyzer.analyze(image, orientation: .up, configuration: .init(.text))
                guard !Task.isCancelled, let self else { return }
                self.recognitionFinished = true
                self.recognizedText = analysis.transcript
                self.overlay.analysis = analysis
                self.overlay.selectableItemsHighlighted = false
                self.status.isHidden = self.quiet || analysis.hasResults(for: .text)
                self.status.stringValue = "未识别到文字"
                self.needsLayout = true
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.recognitionFinished = true
                self.status.stringValue = "识别失败，请重试"
                self.toolTip = "文字识别失败，请重新打开图片"
                self.needsLayout = true
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    deinit { work?.cancel() }
    func stop() { work?.cancel(); work = nil; overlay.analysis = nil; feedback.hide() }
    override func layout() {
        super.layout()
        status.frame = NSRect(x: max(0, (bounds.width-200)/2), y: max(0, (bounds.height-24)/2), width: min(200, bounds.width), height: min(24, bounds.height))
    }
    @discardableResult func copyText(allIfUnselected: Bool, pasteboard: NSPasteboard = .general) -> Bool {
        let selected = overlay.selectedText
        let text = selected.isEmpty && allIfUnselected ? recognizedText : selected
        guard !text.isEmpty else { return false }
        pasteboard.clearContents(); pasteboard.setString(text, forType: .string)
        if pasteboard === NSPasteboard.general { feedback.show() }
        return true
    }
    func overlayView(_ overlayView: ImageAnalysisOverlayView, shouldHandleKeyDownEvent event: NSEvent) -> Bool {
        if event.keyCode == 53 { onCancel?(); return false }
        if event.keyCode == 36 || event.keyCode == 76 {
            if let onConfirm { onConfirm() } else { copyText(allIfUnselected: true) }; return false
        }
        if event.modifierFlags.contains(.command), event.keyCode == 8 {
            copyText(allIfUnselected: false); return false
        }
        return true
    }
    func overlayView(_ overlayView: ImageAnalysisOverlayView, updatedMenuFor menu: NSMenu, for event: NSEvent, at point: CGPoint) -> NSMenu {
        let result = NSMenu()
        let copy = NSMenuItem(title: "复制文字", action: #selector(copySelected), keyEquivalent: "")
        copy.target = self; copy.isEnabled = !overlay.selectedText.isEmpty
        result.autoenablesItems = false; result.addItem(copy)
        let all = NSMenuItem(title: "复制全部文字", action: #selector(copyAll), keyEquivalent: "")
        all.target = self; all.isEnabled = !recognizedText.isEmpty; result.addItem(all)
        return result
    }
    @objc private func copySelected() { copyText(allIfUnselected: false) }
    @objc private func copyAll() {
        guard !recognizedText.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(recognizedText, forType: .string); feedback.show()
    }
}

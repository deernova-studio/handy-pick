import AppKit
import VisionKit
import OSLog

/// On-device Live Text over the exact crop displayed to the user.
@MainActor final class ImageTextSelection: NSImageView, ImageAnalysisOverlayViewDelegate {
    let overlay = ImageAnalysisOverlayView(frame: .zero)
    private let status = NSTextField(labelWithString: "正在识别文字…")
    private static let analyzer = ImageAnalyzer()
    private let progress = NSProgressIndicator()
    private let statusSurface = PaperlightSurface()
    private let retry = NSButton(title: "重试", target: nil, action: nil)
    private var loadingTask: Task<Void, Never>?
    private var loadingShownAt: TimeInterval?
    private var sourceImage: CGImage?
    var onAnalysis: ((ImageAnalysis) -> Void)?
    private var work: Task<Void, Never>?
    private let feedback = CopyFeedback()
    private(set) var recognitionFinished = false
    private(set) var recognizedText = ""
    var onConfirm: (() -> Void)?
    var onUndo: (() -> Void)?
    private let quiet: Bool
    var onCancel: (() -> Void)?

    init(image: CGImage, frame: NSRect, quiet: Bool = false, cached: ImageAnalysis? = nil) {
        self.quiet = quiet
        super.init(frame: frame)
        self.image = NSImage(cgImage: image, size: frame.size)
        imageScaling = .scaleAxesIndependently
        overlay.frame = bounds; overlay.autoresizingMask = [.width, .height]
        overlay.delegate = self; overlay.trackingImageView = self
        overlay.preferredInteractionTypes = .textSelection
        overlay.isSupplementaryInterfaceHidden = true
        addSubview(overlay)
        sourceImage = image
        status.font = Paperlight.caption; status.textColor = Paperlight.secondary
        status.setAccessibilityLabel("文字识别状态")
        statusSurface.fill = Paperlight.raised; statusSurface.radius = 8
        statusSurface.isHidden = true; addSubview(statusSurface)
        progress.style = .spinning; progress.controlSize = .small
        statusSurface.addSubview(progress); statusSurface.addSubview(status)
        retry.bezelStyle = .rounded; retry.controlSize = .small
        retry.target = self; retry.action = #selector(retryRecognition)
        retry.isHidden = true; statusSurface.addSubview(retry)
        if let cached { apply(cached) } else { recognize() }
    }
    private func apply(_ analysis: ImageAnalysis) {
        recognitionFinished = true; recognizedText = analysis.transcript
        overlay.analysis = analysis; overlay.selectableItemsHighlighted = false
        onAnalysis?(analysis)
        loadingTask?.cancel(); progress.stopAnimation(nil); progress.isHidden = true
        let hideStatus = analysis.hasResults(for: .text) || quiet
        if hideStatus, let shown = loadingShownAt, ProcessInfo.processInfo.systemUptime-shown < 0.5 {
            loadingTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, 0.5-(ProcessInfo.processInfo.systemUptime-shown))))
                guard !Task.isCancelled else { return }; self?.statusSurface.isHidden = true
            }
        } else { statusSurface.isHidden = hideStatus }
        status.stringValue = analysis.hasResults(for: .text) ? "可拖选文字" : "未识别到文字"; needsLayout = true
    }
    @objc private func retryRecognition() { recognize() }
    private func recognize() {
        guard let image = sourceImage else { return }
        work?.cancel(); loadingTask?.cancel()
        recognitionFinished = false; loadingShownAt = nil; retry.isHidden = true; statusSurface.isHidden = true
        guard ImageAnalyzer.isSupported else {
            status.stringValue = "此设备不支持文字识别"; recognitionFinished = true
            statusSurface.isHidden = false; return
        }
        loadingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, !self.recognitionFinished else { return }
            self.loadingShownAt = ProcessInfo.processInfo.systemUptime
            self.status.stringValue = "识别文字…"; self.statusSurface.isHidden = false
            self.progress.isHidden = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if !self.progress.isHidden { self.progress.startAnimation(nil) }
            self.needsLayout = true
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, !self.recognitionFinished else { return }
            self.status.stringValue = "仍在识别，可按 Esc 退出"; self.needsLayout = true
        }
        work = Task { [weak self] in
            let started = ProcessInfo.processInfo.systemUptime
            do {
                let analysis = try await Self.analyzer.analyze(image, orientation: .up, configuration: .init(.text))
                guard !Task.isCancelled, let self else { return }
                Logger(subsystem: "studio.deernova.quick-snap", category: "ocr").notice("analysis-seconds=\(ProcessInfo.processInfo.systemUptime-started, privacy: .public)")
                self.apply(analysis)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.loadingTask?.cancel(); self.progress.stopAnimation(nil); self.progress.isHidden = true
                self.recognitionFinished = true; self.status.stringValue = "识别失败"
                self.statusSurface.isHidden = false; self.retry.isHidden = false; self.needsLayout = true
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    deinit { work?.cancel(); loadingTask?.cancel() }
    func stop() { loadingTask?.cancel(); progress.stopAnimation(nil); work?.cancel(); work = nil; overlay.analysis = nil; feedback.hide() }
    override func layout() {
        super.layout()
        let width = min(bounds.width, retry.isHidden ? 220.0 : 180.0)
        statusSurface.frame = NSRect(x: max(0, (bounds.width-width)/2), y: max(0, bounds.height-40), width: width, height: 32)
        progress.frame = NSRect(x: 8, y: 8, width: 16, height: 16)
        status.frame = NSRect(x: 32, y: 8, width: max(0,width-(retry.isHidden ? 40 : 88)), height: 16)
        retry.frame = NSRect(x: width-52, y: 4, width: 48, height: 24)
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
        if event.modifierFlags.contains(.command), event.keyCode == 6, let onUndo {
            onUndo(); return false
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

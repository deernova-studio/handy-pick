import AppKit
import ScreenCaptureKit
import QuickSnapCore

struct ScreenFrame {
    let screen: NSScreen
    let image: CGImage
}

enum CaptureFailure: LocalizedError {
    case noDisplay, invalidSelection
    var errorDescription: String? {
        switch self {
        case .noDisplay: return "没有找到可截图的显示器。"
        case .invalidSelection: return "选区太小，请重新框选。"
        }
    }
}

@MainActor final class CaptureController {
    private var panels: [SelectionPanel] = []
    private var completion: ((CGImage?) -> Void)?
    var active: Bool { !panels.isEmpty }

    func captureScreens() async throws -> [ScreenFrame] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        var result: [ScreenFrame] = []
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            config.captureResolution = .best
            config.ignoreShadowsDisplay = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            result.append(ScreenFrame(screen: screen, image: image))
        }
        guard !result.isEmpty else { throw CaptureFailure.noDisplay }
        return result
    }

    func show(_ frames: [ScreenFrame], completion: @escaping (CGImage?) -> Void) {
        cancel()
        self.completion = completion
        for frame in frames {
            let panel = SelectionPanel(contentRect: frame.screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.isOpaque = true
            panel.backgroundColor = .black
            panel.hasShadow = false
            let view = SelectionView(image: frame.image)
            view.onComplete = { [weak self] image in self?.finish(image) }
            panel.contentView = view
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        let mouse = NSEvent.mouseLocation
        if let panel = panels.first(where: { $0.frame.contains(mouse) }) ?? panels.first {
            panel.makeKey(); panel.makeFirstResponder(panel.contentView)
        }
        NSCursor.crosshair.push()
    }

    func cancel() { if active { finish(nil) } }
    private func finish(_ image: CGImage?) {
        let callback = completion
        completion = nil
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels.removeAll()
        NSCursor.pop()
        callback?(image)
    }

}

final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SelectionView: NSView {
    let image: CGImage
    var onComplete: ((CGImage?) -> Void)?
    private var start: CGPoint?
    private var selection: CGRect = .zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(image: CGImage) { self.image = image; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("Not supported") }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        let picture = NSImage(cgImage: image, size: bounds.size)
        picture.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.black.withAlphaComponent(0.42).setFill(); bounds.fill()
        if selection.width > 0, selection.height > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            picture.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: selection); outline.lineWidth = 1; outline.stroke()
            let text = "\(Int(selection.width)) × \(Int(selection.height))"
            (text as NSString).draw(at: CGPoint(x: selection.minX+6, y: max(6, selection.minY-26)),
                withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white])
        }
        let hint = "拖动框选 · 松开复制 · Esc / 右键取消"
        (hint as NSString).draw(at: CGPoint(x: 24, y: 24),
            withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white])
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey(); window?.makeFirstResponder(self)
        start = convert(event.locationInWindow, from: nil)
        selection = .zero; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        selection = SelectionGeometry.selection(from: start, to: convert(event.locationInWindow, from: nil), in: bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        self.start = nil
        selection = SelectionGeometry.selection(from: start, to: convert(event.locationInWindow, from: nil), in: bounds)
        guard let pixels = SelectionGeometry.pixels(for: selection, logicalSize: bounds.size,
                 pixelSize: CGSize(width: image.width, height: image.height)),
              let cropped = image.cropping(to: pixels) else { selection = .zero; needsDisplay = true; return }
        onComplete?(cropped)
    }
    override func rightMouseDown(with event: NSEvent) { onComplete?(nil) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onComplete?(nil) } else { super.keyDown(with: event) }
    }
}

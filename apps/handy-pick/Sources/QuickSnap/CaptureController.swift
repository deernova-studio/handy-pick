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
            config.ignoreShadowsDisplay = false
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
            panel.animationBehavior = .none
            panel.setFrame(frame.screen.frame, display: false)
            panel.isOpaque = true
            panel.backgroundColor = .black
            panel.hasShadow = false
            let view = SelectionView(image: frame.image)
            view.onComplete = { [weak self] image in self?.finish(image) }
            panel.contentView = view
            panels.append(panel)
            panel.displayIfNeeded()
        }
        // Prepare every display before showing any overlay; never animate or constrain it to the work area.
        panels.forEach { $0.orderFrontRegardless() }
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
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

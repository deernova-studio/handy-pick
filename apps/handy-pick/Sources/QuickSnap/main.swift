import AppKit
import ApplicationServices
import QuickSnapCore
import OSLog

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem!
    private let panel = ShortcutPopover()
    private lazy var shortcutPanel = ShortcutPanel(editor: panel)
    private let trigger = ShortcutTrigger()
    private let capture = CaptureController()
    private let copyFeedback = CopyFeedback()
    private let clipboard = ClipboardMonitor()
    private let historyPreview = HistoryPreview()
    private var recentImage: NSImage?
    private var preparing = false
    private var message = ""
    private let gestureLog = Logger(subsystem: "studio.deernova.quick-snap", category: "gesture")
    private var shortcutMode: ShortcutMode {
        get { ShortcutMode(rawValue: UserDefaults.standard.string(forKey: "shortcutMode") ?? "") ?? .doublePress }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "shortcutMode") }
    }
    private var binding: ShortcutBinding {
        get {
            let key = shortcutMode == .chord ? "chordBinding" : "shortcutBinding"
            if let data = UserDefaults.standard.data(forKey: key),
               let value = try? JSONDecoder().decode(ShortcutBinding.self, from: data), shortcutMode.accepts(value) { return value }
            if shortcutMode == .chord { return .key(35, (1 << 18) | (1 << 19)) } // ⌃⌥P
            let old = UserDefaults.standard.object(forKey: "triggerButton") as? Int ?? 2
            let fallback = ShortcutBinding.mouse(Int64(old))
            return fallback.isValid ? fallback : .mouse(2)
        }
        set {
            guard shortcutMode.accepts(newValue), let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: shortcutMode == .chord ? "chordBinding" : "shortcutBinding")
        }
    }
    private var monitoringWanted: Bool {
        get { UserDefaults.standard.object(forKey: "monitoringEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "monitoringEnabled") }
    }
    private var permissionsReady: Bool { CGPreflightScreenCaptureAccess() && AXIsProcessTrusted() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = MenuBarIcon.make()
        status.button?.setAccessibilityLabel(AppIdentity.displayName)
        status.button?.target = self; status.button?.action = #selector(statusClicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        shortcutPanel.onDismiss = { [weak self] in
            self?.trigger.cancelRecording(); self?.refresh()
        }
        shortcutPanel.isRecording = { [weak self] in self?.trigger.recording ?? false }
        trigger.onRecordingHint = { [weak self] in self?.panel.showRecordingHint($0) }
        panel.onSizeChange = { [weak self] size in self?.shortcutPanel.resize(to: size) }
        clipboard.onChange = { [weak self] entries in
            self?.panel.updateHistory(entries)
            self?.historyPreview.retainOnly(Set(entries.map(\.id)))
        }
        historyPreview.onDismiss = { [weak self] in
            guard let self else { return }
            self.trigger.suspended = self.capture.active || self.preparing
        }
        historyPreview.onEditedImage = { [weak self] image in
            guard let self else { return }
            self.recentImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            self.copyRecent()
            self.inform("标注图片已复制")
        }
        panel.onPreview = { [weak self] id in
            guard let self, let entry = self.clipboard.history.entries.first(where: { $0.id == id }) else { return }
            self.shortcutPanel.dismiss()
            self.historyPreview.show(entry)
            self.trigger.suspended = true
        }
        panel.onSelect = { [weak self] id in
            guard let self else { return }
            if self.clipboard.select(id) { self.shortcutPanel.dismiss(); self.copyFeedback.show() }
        }
        panel.onRemove = { [weak self] id in self?.clipboard.remove(id) }
        panel.onClear = { [weak self] in self?.clipboard.clear() }
        clipboard.start()
        panel.onRecord = { [weak self] in self?.beginRecording() }
        panel.onModeChange = { [weak self] mode in
            guard let self else { return }
            self.shortcutMode = mode
            self.startMonitoring()
        }
        panel.onPermission = { [weak self] in self?.requestPermission() }
        trigger.onAction = { [weak self] in self?.handleShortcut($0) }
        trigger.onRecorded = { [weak self] value in
            guard let self else { return }
            if let value { self.binding = value }
            self.startMonitoring()
            if value != nil { self.inform("已保存") }
        }
        startMonitoring()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { false }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            shortcutPanel.dismiss()
            status.menu = makeMenu(); status.button?.performClick(nil); status.menu = nil
        } else { togglePopover() }
    }

    private func togglePopover() {
        if shortcutPanel.isVisible { shortcutPanel.dismiss(); return }
        historyPreview.dismiss()
        guard let button = status.button else { return }
        refresh()
        shortcutPanel.show(below: button)
    }

    private func refresh() {
        status.button?.toolTip = "\(AppIdentity.displayName) · \(shortcutMode == .doublePress ? "双击" : "按下")\(binding.displayName)复制 / 粘贴 / 截图\n\(message)"
        panel.update(binding: binding.displayName, recording: trigger.recording, needsPermission: !permissionsReady, mode: shortcutMode)
    }
    private func inform(_ text: String) { message = text; refresh() }

    private func recordGestureOutcome(_ outcome: String) {
        gestureLog.notice("\(outcome, privacy: .public)")
        // A single local status code remains available when unified logging is disabled.
        // It contains no input text, image, application identifier or control content.
        UserDefaults.standard.set(outcome, forKey: "lastGestureOutcome")
    }

    private func startMonitoring() {
        trigger.stop(); trigger.mode = shortcutMode; trigger.binding = binding
        trigger.suspended = historyPreview.window != nil
        guard permissionsReady else { inform("需要屏幕录制和辅助功能权限"); return }
        guard monitoringWanted else { inform("已暂停"); return }
        inform(trigger.start(active: true) ? "已启用" : "无法监听，请检查辅助功能权限")
    }

    private func beginRecording() {
        guard AXIsProcessTrusted() else { requestPermission(); return }
        if trigger.beginRecording() { inform("录入后立即保存") }
        else { inform("无法录入，请检查辅助功能权限") }
    }

    @objc private func toggle() {
        monitoringWanted = !trigger.running
        capture.cancel(); startMonitoring()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "\(shortcutMode == .doublePress ? "双击" : "按下")\(binding.displayName)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        add("更换快捷键…", #selector(openRecorder), to: menu)
        add("开始截图", #selector(startFromMenu), to: menu)
        let copy = add("复制最近截图", #selector(copyRecent), to: menu); copy.isEnabled = recentImage != nil
        add("清空剪贴板记录", #selector(clearHistory), to: menu)
        add(trigger.running ? "暂停" : "启用", #selector(toggle), to: menu)
        if !permissionsReady { add("授予权限…", #selector(requestPermission), to: menu) }
        menu.addItem(.separator()); add("退出 \(AppIdentity.displayName)", #selector(quit), to: menu)
        return menu
    }
    @discardableResult private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item); return item
    }
    @objc private func clearHistory() { clipboard.clear() }
    @objc private func openRecorder() { DispatchQueue.main.async { self.togglePopover() } }

    @objc private func startFromMenu() {
        historyPreview.dismiss()
        shortcutPanel.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now()+0.15) { self.beginCapture() }
    }
    private func beginCapture() {
        guard !capture.active, !preparing else { return }
        guard CGPreflightScreenCaptureAccess() else { inform("请先授予屏幕录制权限"); return }
        copyFeedback.hide()
        shortcutPanel.dismiss(); preparing = true; trigger.suspended = true
        Task {
            defer { preparing = false }
            do {
                let frames = try await capture.captureScreens()
                capture.show(frames) { [weak self] image in
                    guard let self else { return }
                    self.trigger.suspended = false
                    guard let image else { self.inform("已取消"); return }
                    self.recentImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                    self.copyRecent(); self.inform("截图已复制")
                    NSSound(named: "Pop")?.play()
                }
            } catch { trigger.suspended = false; inform("截图失败：\(error.localizedDescription)") }
        }
    }
    private func handleShortcut(_ gesture: ClickRecognizer.Gesture) {
        guard trigger.running, !capture.active, !preparing else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == gesture.target else {
            recordGestureOutcome("foreground-changed")
            return
        }
        shortcutPanel.dismiss()
        preparing = true
        Task { [weak self] in
            guard let self else { return }
            let action = await InputTarget.resolve(at: gesture.point, foregroundPID: gesture.target)
            guard self.trigger.running, !self.capture.active,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == gesture.target else {
                self.preparing = false; return
            }
            let input: InputTarget
            switch action {
            case .copy(let text):
                self.preparing = false
                NSPasteboard.general.clearContents()
                if NSPasteboard.general.setString(text, forType: .string) {
                    self.clipboard.poll()
                    self.recordGestureOutcome("selected-text-copied")
                    self.inform("已复制选中文字")
                    self.copyFeedback.show()
                } else { self.inform("复制失败，请重试") }
                return
            case .unavailable:
                self.preparing = false; return
            case .capture:
                self.preparing = false
                self.recordGestureOutcome("no-input-capture")
                self.beginCapture(); return
            case .paste(let target): input = target
            }
            defer { self.preparing = false }
            guard input.copyTerminalSelectionFirst || !(NSPasteboard.general.types?.isEmpty ?? true) else {
                self.recordGestureOutcome("input-found-empty-clipboard")
                self.inform("剪贴板为空"); NSSound.beep(); return
            }
            self.recordGestureOutcome("input-found-focus-pending")
            input.focus()
            // Native and web editors may update accessibility focus asynchronously.
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(60))
                guard self.trigger.running, !self.capture.active else { return }
                if input.isFocused() {
                    if input.copyTerminalSelectionFirst {
                        await self.copyOrPasteTerminal(input, at: gesture.point)
                    } else { self.paste(to: input.pid) }
                    return
                }
            }
            self.recordGestureOutcome("input-found-focus-unconfirmed")
            self.inform("请先点入输入框再使用快捷键")
        }
    }

    private func copyOrPasteTerminal(_ input: InputTarget, at point: CGPoint) async {
        guard input.isFocused() else { return }
        let changeCount = NSPasteboard.general.changeCount
        // macOS uses the native copy event; Codex's Ctrl-Shift-C clipboard
        // handler is enabled only on non-macOS platforms. Never send Ctrl-C.
        postShortcut(key: 8, flags: .maskCommand)
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(50))
            guard trigger.running, !capture.active, input.isFocused() else { return }
            if NSPasteboard.general.changeCount != changeCount {
                clipboard.poll()
                recordGestureOutcome("terminal-selection-copied")
                inform("已复制选中文字"); copyFeedback.show()
                return
            }
        }
        // Recheck the same terminal surface before the fallback paste, so a
        // focus change or panel closing during the async copy cannot redirect it.
        guard let current = InputTarget.at(point), current.copyTerminalSelectionFirst,
              current.pid == input.pid, CFEqual(current.element, input.element), input.isFocused() else { return }
        // Clipboard writers can run while the synchronous AX recheck is waiting.
        // Do not paste if the copy completed (or another writer intervened) then.
        guard NSPasteboard.general.changeCount == changeCount else { return }
        guard !(NSPasteboard.general.types?.isEmpty ?? true) else {
            recordGestureOutcome("input-found-empty-clipboard"); inform("剪贴板为空"); return
        }
        paste(to: input.pid)
    }

    @objc private func copyRecent() {
        guard let recentImage, let cg = recentImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setData(png, forType: .png) else { inform("复制失败，请重试"); return }
        if let tiff = recentImage.tiffRepresentation { NSPasteboard.general.setData(tiff, forType: .tiff) }
        clipboard.poll()
        copyFeedback.show()
    }
    private func paste(to pid: Int32) {
        guard AXIsProcessTrusted(), pid > 0,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        postShortcut(key: 9, flags: .maskCommand)
        recordGestureOutcome("paste-shortcut-posted")
        inform("已发送粘贴")
    }
    private func postShortcut(key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags; up?.flags = flags
        down?.setIntegerValueField(.eventSourceUserData, value: ShortcutTrigger.syntheticEventTag)
        up?.setIntegerValueField(.eventSourceUserData, value: ShortcutTrigger.syntheticEventTag)
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
    }

    @objc private func requestPermission() {
        shortcutPanel.dismiss()
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            openSettings("Privacy_Accessibility")
        } else if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess(); openSettings("Privacy_ScreenCapture")
        } else { startMonitoring() }
    }
    private func openSettings(_ section: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") { NSWorkspace.shared.open(url) }
    }
    @objc private func quit() { trigger.stop(); capture.cancel(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { trigger.stop(); historyPreview.dismiss(); clipboard.stop(); clipboard.clear() }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}

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
    private var routingTask: Task<Void, Never>?
    private var editChoice: EditChoicePanel?
    private var captureTask: Task<Void, Never>?
    private var captureGeneration = 0
    private var permissionTimer: Timer?
    private var lastPermissionsReady = false
    private var recordingAction: ShortcutAction?
    private let shortcutSettings = ShortcutSettings()
    private var shortcutDescriptions: [String] {
        let prefix = shortcutMode == .doublePress ? "双击" : "按下"
        var described: [ShortcutBinding] = []
        return ShortcutAction.allCases.compactMap { action in
            guard let binding = trigger.bindings[action], !described.contains(binding) else { return nil }
            described.append(binding)
            let titles = ShortcutAction.allCases.filter { trigger.bindings[$0] == binding }.map(\.title)
            return "\(prefix)\(binding.displayName) \(titles.joined(separator: " / "))"
        }
    }
    private var message = ""
    private let gestureLog = Logger(subsystem: "studio.deernova.quick-snap", category: "gesture")
    private var shortcutMode: ShortcutMode {
        get { ShortcutMode(rawValue: UserDefaults.standard.string(forKey: "shortcutMode") ?? "") ?? .doublePress }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "shortcutMode") }
    }
    private var monitoringWanted: Bool {
        get { UserDefaults.standard.object(forKey: "monitoringEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "monitoringEnabled") }
    }
    private var permissionsReady: Bool { AXIsProcessTrusted() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = MenuBarIcon.make()
        status.button?.setAccessibilityLabel(AppIdentity.displayName)
        status.button?.target = self; status.button?.action = #selector(statusClicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        panel.onSettingsCollapsed = { [weak self] in
            guard let self, self.recordingAction != nil else { return }
            self.recordingAction = nil
            self.trigger.cancelRecording()
            self.refresh()
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
            self.updateSuspension()
        }
        historyPreview.onFocusChange = { [weak self] in self?.updateSuspension() }
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
            self.updateSuspension()
        }
        panel.onSelect = { [weak self] id in
            guard let self else { return }
            if self.clipboard.select(id) { self.shortcutPanel.dismiss(); self.copyFeedback.show() }
        }
        panel.onRemove = { [weak self] id in self?.clipboard.remove(id) }
        panel.onClear = { [weak self] in self?.clipboard.clear() }
        clipboard.start()
        panel.onRecord = { [weak self] action in self?.beginRecording(action) }
        panel.onModeChange = { [weak self] mode in
            guard let self else { return }
            self.shortcutMode = mode
            self.startMonitoring()
        }
        panel.onPermission = { [weak self] in self?.requestPermission() }
        trigger.onAction = { [weak self] actions, pid, point in self?.handleShortcut(actions, target: pid, at: point) }
        trigger.onInteractionWhileSuspended = { [weak self] interruption in
            guard let self, self.editChoice?.isVisible != true || interruption == .applicationChange else { return }
            self.cancelRouting()
        }
        trigger.onRecorded = { [weak self] value in
            guard let self, let action = self.recordingAction else { return }
            let saved = value.map { self.shortcutSettings.save($0, for: action, mode: self.shortcutMode) }
            self.startMonitoring()
            if let saved { self.inform(saved ? "已保存" : "快捷键无效，请重新录入") }
        }
        startMonitoring()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcilePermissions() }
        }
        timer.tolerance = 0.2
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { false }

    @objc private func statusClicked() {
        reconcilePermissions()
        if NSApp.currentEvent?.type == .rightMouseUp {
            shortcutPanel.dismiss()
            status.menu = makeMenu(); status.button?.performClick(nil); status.menu = nil
        } else if shortcutPanel.isVisible {
            shortcutPanel.dismiss()
        } else {
            showPopover()
        }
    }

    private func showPopover(settingsExpanded: Bool = false) {
        cancelRouting()
        historyPreview.dismiss()
        guard let button = status.button else { return }
        refresh()
        panel.setSettingsExpanded(settingsExpanded)
        if !shortcutPanel.isVisible { shortcutPanel.show(below: button) }
    }

    private func refresh() {
        let shortcuts = shortcutDescriptions.joined(separator: " · ")
        status.button?.toolTip = "\(AppIdentity.displayName) · \(shortcuts)\n\(message)"
        panel.update(bindings: trigger.bindings, recording: trigger.recording ? recordingAction : nil,
                     needsPermission: !permissionsReady, mode: shortcutMode)
    }
    private func inform(_ text: String) { message = text; refresh() }

    private func recordGestureOutcome(_ outcome: String) {
        gestureLog.notice("\(outcome, privacy: .public)")
        // A single local status code remains available when unified logging is disabled.
        // It contains no input text, image, application identifier or control content.
        UserDefaults.standard.set(outcome, forKey: "lastGestureOutcome")
    }

    private func updateSuspension() {
        trigger.suspended = routingTask != nil || capture.active || captureTask != nil || historyPreview.window?.isKeyWindow == true
    }

    private func reconcilePermissions() {
        guard permissionsReady != lastPermissionsReady else { return }
        startMonitoring()
    }

    private func cancelCapture() {
        captureGeneration &+= 1
        captureTask?.cancel()
        captureTask = nil
        capture.cancel()
        updateSuspension()
    }

    private func startMonitoring() {
        cancelRouting()
        cancelCapture()
        recordingAction = nil
        trigger.stop()
        trigger.mode = shortcutMode
        trigger.bindings = shortcutSettings.bindings(for: shortcutMode)
        updateSuspension()
        lastPermissionsReady = permissionsReady
        guard lastPermissionsReady else { inform("需要辅助功能权限才能使用快捷键"); return }
        guard monitoringWanted else { inform("已暂停"); return }
        inform(trigger.start(active: true) ? "已启用" : "无法监听，请检查辅助功能权限")
    }

    private func beginRecording(_ action: ShortcutAction) {
        guard AXIsProcessTrusted() else { requestPermission(); return }
        cancelRouting()
        recordingAction = action
        if trigger.beginRecording() {
            inform("录入后立即保存")
        } else {
            recordingAction = nil
            inform("无法录入，请检查辅助功能权限")
        }
    }

    @objc private func toggle() {
        monitoringWanted = !trigger.running
        startMonitoring()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        for description in shortcutDescriptions {
            menu.addItem(withTitle: description, action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        add("更换快捷键…", #selector(openRecorder), to: menu)
        add("开始截图", #selector(startFromMenu), to: menu)
        let copy = add("复制最近截图", #selector(copyRecent), to: menu); copy.isEnabled = recentImage != nil
        add("清空剪贴板记录", #selector(clearHistory), to: menu)
        add(trigger.running ? "暂停" : "启用", #selector(toggle), to: menu)
        if !permissionsReady || !CGPreflightScreenCaptureAccess() { add("授予权限…", #selector(requestPermission), to: menu) }
        menu.addItem(.separator()); add("退出 \(AppIdentity.displayName)", #selector(quit), to: menu)
        return menu
    }
    @discardableResult private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item); return item
    }
    @objc private func clearHistory() { clipboard.clear() }
    @objc private func openRecorder() { DispatchQueue.main.async { self.showPopover(settingsExpanded: true) } }

    @objc private func startFromMenu() {
        cancelRouting()
        historyPreview.dismiss()
        shortcutPanel.dismiss()
        beginCapture(delay: .milliseconds(150))
    }
    private func beginCapture(delay: Duration = .zero) {
        guard !capture.active, captureTask == nil else { return }
        guard CGPreflightScreenCaptureAccess() else { requestScreenCapturePermission(); return }
        copyFeedback.hide()
        shortcutPanel.dismiss()
        captureGeneration &+= 1
        let generation = captureGeneration
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == captureGeneration {
                    captureTask = nil
                    updateSuspension()
                }
            }
            do {
                if delay > .zero { try await Task.sleep(for: delay) }
                try Task.checkCancellation()
                let frames = try await capture.captureScreens()
                try Task.checkCancellation()
                guard generation == captureGeneration else { return }
                capture.show(frames) { [weak self] image in
                    guard let self, generation == self.captureGeneration else { return }
                    self.updateSuspension()
                    guard let image else { self.inform("已取消"); return }
                    self.recentImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                    self.copyRecent(); self.inform("截图已复制")
                    NSSound(named: "Pop")?.play()
                }
            } catch {
                guard generation == captureGeneration, !Task.isCancelled else { return }
                inform("截图失败：\(error.localizedDescription)")
            }
        }
        updateSuspension()
    }
    private func handleShortcut(_ actions: Set<ShortcutAction>, target pid: pid_t, at point: CGPoint) {
        guard trigger.running, routingTask == nil, !capture.active, captureTask == nil, pid > 0,
              pid != ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        shortcutPanel.dismiss()
        if actions.count == 1, let action = actions.first {
            performShortcut(action, target: pid)
            return
        }
        routingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if !Task.isCancelled {
                    routingTask = nil
                    updateSuspension()
                }
            }
            let action = await InputTarget.resolve(at: point, foregroundPID: pid, actions: actions)
            guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            switch action {
            case .copy(let text):
                NSPasteboard.general.clearContents()
                if NSPasteboard.general.setString(text, forType: .string) {
                    clipboard.poll()
                    recordGestureOutcome("selected-text-copied")
                    inform("已复制选中文字")
                    copyFeedback.show()
                } else { inform("复制失败，请重试") }
            case .copyFocused(let input):
                if await input.isFocused(), !Task.isCancelled {
                    performShortcut(.copy, target: pid)
                } else if !Task.isCancelled {
                    inform("请先聚焦选区所在的控件再复制")
                }
            case .chooseCopyOrPaste(let input):
                await chooseTerminalAction(in: input)
            case .paste(let input):
                guard !(NSPasteboard.general.types?.isEmpty ?? true) else { inform("剪贴板为空"); return }
                if await input.focusForPaste(), !Task.isCancelled {
                    performShortcut(.paste, target: pid)
                } else if !Task.isCancelled {
                    inform("请先点入输入框再使用快捷键")
                }
            case .capture:
                performShortcut(.capture, target: pid)
            case .unknownSelection:
                recordGestureOutcome("shared-shortcut-selection-unknown")
                inform("无法确认选区，请使用独立复制或粘贴键")
            case .unavailable:
                recordGestureOutcome("shared-shortcut-unresolved")
                inform("未找到匹配的动作")
            }
        }
        updateSuspension()
    }

    private func cancelRouting() {
        guard let routingTask else { return }
        routingTask.cancel()
        editChoice?.dismiss()
        editChoice = nil
        self.routingTask = nil
        updateSuspension()
    }

    private func chooseTerminalAction(in input: InputTarget) async {
        guard await input.isFocused(), !Task.isCancelled else { return }
        let panel = EditChoicePanel()
        editChoice = panel
        let choice = await panel.choose(at: NSEvent.mouseLocation)
        if editChoice === panel { editChoice = nil }
        guard let choice, !Task.isCancelled,
              await input.isFocused(), !Task.isCancelled else { return }
        performShortcut(choice, target: input.pid)
    }

    private func performShortcut(_ action: ShortcutAction, target pid: pid_t) {
        switch action {
        case .copy:
            if postShortcut(key: 8, to: pid) { // C
                recordGestureOutcome("copy-shortcut-posted")
                inform("已发送复制")
            }
        case .paste:
            if postShortcut(key: 9, to: pid) { // V
                recordGestureOutcome("paste-shortcut-posted")
                inform("已发送粘贴")
            }
        case .capture:
            recordGestureOutcome("capture-shortcut-started")
            beginCapture()
        }
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
    private func postShortcut(key: CGKeyCode, to pid: pid_t) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard AXIsProcessTrusted(),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        for event in [down, up] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: ShortcutTrigger.syntheticEventTag)
            event.postToPid(pid)
        }
        return true
    }

    @objc private func requestPermission() {
        shortcutPanel.dismiss()
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            openSettings("Privacy_Accessibility")
        } else if !CGPreflightScreenCaptureAccess() {
            requestScreenCapturePermission()
        } else { startMonitoring() }
    }
    private func requestScreenCapturePermission() {
        shortcutPanel.dismiss()
        inform("请先授予屏幕录制权限")
        _ = CGRequestScreenCaptureAccess()
        openSettings("Privacy_ScreenCapture")
    }

    private func openSettings(_ section: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") { NSWorkspace.shared.open(url) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        cancelRouting()
        cancelCapture()
        trigger.stop()
        historyPreview.dismiss()
        clipboard.stop()
        clipboard.clear()
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}

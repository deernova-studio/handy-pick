import AppKit
import ApplicationServices
import QuickSnapCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem!
    private let mouse = MouseTrigger()
    private let capture = CaptureController()
    private var recentImage: NSImage?
    private var preparing = false
    private var window: NSWindow?
    private var stateLabel: NSTextField?
    private var diagnosticLabel: NSTextField?
    private var buttonPicker: NSPopUpButton?
    private var toggleButton: NSButton?
    private var message = "尚未开启"
    private let buttonOptions = [(2, "鼠标中键（按下滚轮）"), (3, "鼠标侧键 4"), (4, "鼠标侧键 5")]
    private var monitoringWanted: Bool {
        get { UserDefaults.standard.object(forKey: "monitoringEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "monitoringEnabled") }
    }
    private var button: Int {
        get { UserDefaults.standard.object(forKey: "triggerButton") as? Int ?? 2 }
        set { UserDefaults.standard.set(newValue, forKey: "triggerButton") }
    }
    private var buttonName: String { [2: "鼠标中键", 3: "鼠标侧键 4", 4: "鼠标侧键 5"][button] ?? "鼠标中键" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if ![2, 3, 4].contains(button) { button = 2 }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Quick Snap")
        status.button?.title = "QS"
        status.button?.imagePosition = .imageLeading
        status.button?.toolTip = "Quick Snap · 双击鼠标按键截图或粘贴"
        mouse.onAction = { [weak self] gesture in self?.handleDoubleClick(gesture) }
        mouse.onObservation = { [weak self] in self?.refreshDiagnostic() }
        if monitoringWanted { startMonitoring() }
        else { inform("已暂停") }
        // A menu-bar utility: launching and reopening never create or activate a window.
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }

    private func refreshMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Quick Snap · \(message)", action: nil, keyEquivalent: "")
        menu.addItem(title); menu.addItem(.separator())
        add("开始截图", #selector(startFromMenu), to: menu)
        let copy = add("复制最近截图", #selector(copyRecent), to: menu); copy.isEnabled = recentImage != nil
        menu.addItem(.separator())
        add(mouse.running ? "暂停快捷操作" : "开启快捷操作", #selector(toggle), to: menu)
        let buttons = NSMenuItem(title: "双击按键：\(buttonName)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (value, name) in buttonOptions {
            let item = add(name, #selector(changeButton(_:)), to: submenu)
            item.tag = value; item.state = value == button ? .on : .off
        }
        buttons.submenu = submenu; menu.addItem(buttons)
        add("设置…", #selector(showSettings), to: menu)
        menu.addItem(.separator())
        add("退出 Quick Snap", #selector(quit), key: "q", to: menu)
        status.menu = menu
        stateLabel?.stringValue = message
        buttonPicker?.selectItem(withTag: button)
        toggleButton?.title = mouse.running ? "暂停快捷操作" : "开启快捷操作"
        refreshDiagnostic()
    }

    private func refreshDiagnostic() {
        let latest = mouse.lastButton.map { " · 最近按键：\($0 + 1)" } ?? ""
        diagnosticLabel?.stringValue = "监听\(mouse.enabled ? "运行中" : "未运行") · 收到辅助按键 \(mouse.pressCount) 次\(latest)"
    }

    @discardableResult private func add(_ title: String, _ action: Selector, key: String = "", to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item); return item
    }
    private func inform(_ text: String) { message = text; refreshMenu() }

    @objc private func toggle() {
        if mouse.running {
            monitoringWanted = false
            mouse.stop(); capture.cancel(); inform("已暂停"); return
        }
        monitoringWanted = true
        startMonitoring()
        if !mouse.running { showSettings() }
    }
    private func startMonitoring() {
        guard CGPreflightScreenCaptureAccess(), AXIsProcessTrusted() else {
            inform("请在设置中授予屏幕录制和辅助功能权限"); return
        }
        mouse.button = Int64(button)
        inform(mouse.start() ? "已开启" : "无法监听，请检查辅助功能 / 输入监控权限")
    }
    @objc private func changeButton(_ sender: NSMenuItem) {
        setButton(sender.tag)
    }
    @objc private func chooseButton(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        setButton(item.tag)
    }
    private func setButton(_ value: Int) {
        guard buttonOptions.contains(where: { $0.0 == value }) else { return }
        let wasRunning = mouse.running
        mouse.stop(); button = value; mouse.button = Int64(button)
        if wasRunning { inform(mouse.start() ? "已开启" : "监听失败，请检查权限") }
        else { refreshMenu() }
    }
    @objc private func startFromMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now()+0.15) { self.beginCapture() }
    }
    private func beginCapture() {
        guard !capture.active, !preparing else { return }
        guard CGPreflightScreenCaptureAccess() else { inform("请先授予屏幕录制权限"); showSettings(); return }
        preparing = true
        window?.orderOut(nil)
        Task {
            defer { preparing = false }
            do { let frames = try await capture.captureScreens(); present(frames) }
            catch { inform("截图失败：\(error.localizedDescription)"); showSettings() }
        }
    }
    private func handleDoubleClick(_ gesture: ClickRecognizer.Gesture) {
        guard mouse.running, !capture.active, !preparing,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == gesture.target else { return }
        guard let input = InputTarget.at(gesture.point) else { beginCapture(); return }
        guard recentImage != nil else {
            inform("还没有截图，请在输入框外双击\(buttonName)截图")
            NSSound.beep()
            return
        }
        preparing = true
        input.focus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            defer { self.preparing = false }
            guard self.mouse.running, input.isFocused() else {
                self.inform("请先点入该输入框，再双击\(self.buttonName)粘贴")
                return
            }
            self.paste(to: input.pid)
        }
    }
    private func present(_ frames: [ScreenFrame]) {
        capture.show(frames) { [weak self] image in
            guard let self else { return }
            guard let image else { self.inform("已取消"); return }
            self.recentImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            self.copyRecent()
            self.inform("截图已复制，可双击\(self.buttonName)粘贴")
            NSSound(named: "Pop")?.play()
        }
    }
    @objc private func copyRecent() {
        guard let recentImage,
              let cg = recentImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        if let tiff = recentImage.tiffRepresentation { NSPasteboard.general.setData(tiff, forType: .tiff) }
    }
    private func paste(to pid: Int32) {
        guard recentImage != nil else { inform("还没有截图，请在输入框外双击\(buttonName)截图"); return }
        guard AXIsProcessTrusted(), pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            inform("请先将光标放到目标输入框"); return
        }
        copyRecent()
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        // Paste only: never press Enter or send a chat message.
        inform("已粘贴最近截图")
    }

    @objc private func showSettings() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); refreshMenu(); return }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 410),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        panel.title = "Quick Snap 设置"; panel.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 26, bottom: 24, right: 26)
        func label(_ text: String, size: CGFloat = 14, bold: Bool = false) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
            field.widthAnchor.constraint(equalToConstant: 388).isActive = true
            stack.addArrangedSubview(field); return field
        }
        _ = label("Quick Snap", size: 24, bold: true)
        let keyRow = NSStackView(); keyRow.orientation = .horizontal; keyRow.spacing = 12
        keyRow.addArrangedSubview(NSTextField(labelWithString: "双击鼠标按键"))
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        for (value, name) in buttonOptions { picker.addItem(withTitle: name); picker.lastItem?.tag = value }
        picker.target = self; picker.action = #selector(chooseButton(_:)); picker.selectItem(withTag: button)
        picker.setAccessibilityLabel("双击鼠标按键")
        keyRow.addArrangedSubview(picker); buttonPicker = picker
        stack.addArrangedSubview(keyRow)
        _ = label("输入区外双击 → 左键框选截图，松开复制\n输入区内双击 → 粘贴最近截图\nEsc 或右键取消框选。", size: 13)
        let toggle = NSButton(title: "", target: self, action: #selector(toggle))
        toggleButton = toggle; stack.addArrangedSubview(toggle)
        stateLabel = label(message, size: 12)
        stateLabel?.textColor = .secondaryLabelColor
        let permissions = NSStackView(); permissions.orientation = .horizontal; permissions.spacing = 10
        permissions.addArrangedSubview(NSButton(title: "屏幕录制权限…", target: self, action: #selector(screenPermission)))
        permissions.addArrangedSubview(NSButton(title: "辅助功能权限…", target: self, action: #selector(accessibilityPermission)))
        stack.addArrangedSubview(permissions)
        diagnosticLabel = label("", size: 12)
        diagnosticLabel?.textColor = .secondaryLabelColor
        _ = label("关闭设置后继续在菜单栏运行，暂停状态和按键会被记住。", size: 12)
        panel.contentView = stack; panel.center(); window = panel
        refreshMenu()
        panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func screenPermission() {
        _ = CGRequestScreenCaptureAccess()
        openSettings("Privacy_ScreenCapture")
    }
    @objc private func accessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSettings("Privacy_Accessibility")
    }
    private func openSettings(_ section: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") { NSWorkspace.shared.open(url) }
    }
    @objc private func quit() { mouse.stop(); capture.cancel(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { mouse.stop() }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}

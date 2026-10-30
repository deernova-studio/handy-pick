import AppKit

final class ShortcutPopover: NSViewController {
    var onRecord: (() -> Void)?
    var onToggle: (() -> Void)?
    var onQuit: (() -> Void)?
    var onPermission: (() -> Void)?
    private let bindingButton = NSButton(title: "", target: nil, action: nil)
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let state = NSTextField(wrappingLabelWithString: "")
    private let toggleButton = NSButton(title: "暂停", target: nil, action: nil)
    private let permissionButton = NSButton(title: "授权…", target: nil, action: nil)

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 14, right: 20)
        let title = NSTextField(labelWithString: "双击快捷键")
        title.font = .systemFont(ofSize: 12, weight: .medium); title.textColor = .secondaryLabelColor
        stack.addArrangedSubview(title)
        bindingButton.target = self; bindingButton.action = #selector(record)
        bindingButton.font = .systemFont(ofSize: 18, weight: .semibold)
        bindingButton.bezelStyle = .rounded
        bindingButton.setAccessibilityLabel("录入双击快捷键")
        bindingButton.widthAnchor.constraint(equalToConstant: 254).isActive = true
        bindingButton.heightAnchor.constraint(equalToConstant: 42).isActive = true
        stack.addArrangedSubview(bindingButton)
        for label in [hint, state] {
            label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor
            label.alignment = .center; label.widthAnchor.constraint(equalToConstant: 254).isActive = true
            stack.addArrangedSubview(label)
        }
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 22
        for (button, action) in [(toggleButton, #selector(toggle)), (permissionButton, #selector(permission))] {
            button.target = self; button.action = action; button.isBordered = false
            button.font = .systemFont(ofSize: 11); row.addArrangedSubview(button)
        }
        let quit = NSButton(title: "退出", target: self, action: #selector(quit))
        quit.isBordered = false; quit.font = .systemFont(ofSize: 11); row.addArrangedSubview(quit)
        stack.addArrangedSubview(row)
        view = stack
        preferredContentSize = NSSize(width: 294, height: 202)
    }

    func update(binding: String, recording: Bool, running: Bool, message: String, needsPermission: Bool) {
        loadViewIfNeeded()
        bindingButton.title = recording ? "请按一个按键…" : binding
        hint.stringValue = recording ? "按中键、侧键或键盘按键；Esc 取消\n所选普通按键启用期间专用于截图 / 粘贴" : "点上方更换 · 统一双击触发\n输入区外截图，输入区内粘贴"
        state.stringValue = message
        toggleButton.title = running ? "暂停" : "启用"
        toggleButton.isEnabled = !recording
        permissionButton.isHidden = !needsPermission
    }

    @objc private func record() { onRecord?() }
    @objc private func toggle() { onToggle?() }
    @objc private func quit() { onQuit?() }
    @objc private func permission() { onPermission?() }
}

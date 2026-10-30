import AppKit

final class ShortcutPopover: NSViewController {
    var onRecord: (() -> Void)?
    var onPermission: (() -> Void)?
    private let caption = NSTextField(labelWithString: "双击")
    private let bindingButton = NSButton(title: "", target: nil, action: nil)
    private var needsPermission = false

    override func loadView() {
        let row = NSStackView(frame: NSRect(x: 0, y: 0, width: 210, height: 52))
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        caption.font = .systemFont(ofSize: 12); caption.textColor = .secondaryLabelColor
        row.addArrangedSubview(caption)
        bindingButton.target = self; bindingButton.action = #selector(record)
        bindingButton.font = .systemFont(ofSize: 13, weight: .medium)
        bindingButton.bezelStyle = .rounded
        bindingButton.setAccessibilityLabel("双击快捷键")
        bindingButton.toolTip = "点击后按新键，Esc 取消"
        bindingButton.widthAnchor.constraint(equalToConstant: 140).isActive = true
        bindingButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        row.addArrangedSubview(bindingButton)
        view = row
        preferredContentSize = NSSize(width: 210, height: 52)
    }

    func update(binding: String, recording: Bool, needsPermission: Bool) {
        loadViewIfNeeded()
        self.needsPermission = needsPermission
        caption.stringValue = needsPermission ? "权限" : "双击"
        bindingButton.title = needsPermission ? "授权…" : (recording ? "按键…" : binding)
    }

    @objc private func record() {
        if needsPermission { onPermission?() }
        else { onRecord?() }
    }
}

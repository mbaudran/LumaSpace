import AppKit

/// Shown over the preview until Screen Recording is allowed.
@MainActor
final class PermissionView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.94).cgColor

        let title = NSTextField(labelWithString: "Allow Screen Recording")
        title.font = .systemFont(ofSize: 26, weight: .semibold)
        let body = NSTextField(wrappingLabelWithString:
            "LumaSpace shows your windows and displays as virtual screens in your glasses, so macOS needs to let it record the screen. Allow LumaSpace in System Settings, then reopen it.")
        body.font = .systemFont(ofSize: 15)
        body.textColor = .secondaryLabelColor
        body.alignment = .center
        let button = NSButton(title: "Open System Settings", target: self, action: #selector(openSettings))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"

        let stack = NSStackView(views: [title, body, button])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            body.widthAnchor.constraint(equalToConstant: 460),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func openSettings() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

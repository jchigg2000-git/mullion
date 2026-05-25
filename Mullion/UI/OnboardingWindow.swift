import AppKit

final class OnboardingWindow: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Mullion"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.contentView = makeContentView()
    }

    private func makeContentView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))

        let title = NSTextField(labelWithString: "Mullion needs Accessibility access")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.frame = NSRect(x: 24, y: 296, width: 472, height: 28)
        container.addSubview(title)

        let body = NSTextField(wrappingLabelWithString: """
        macOS requires Accessibility permission for Mullion to move and resize windows on your behalf.

        1. Click Open System Settings below.
        2. Toggle Mullion on under Privacy & Security → Accessibility.
        3. Return here — Mullion detects the change automatically.

        If toggling doesn't take effect (e.g., after upgrading), click Quit & Reopen and grant again on the next launch.
        """)
        body.font = .systemFont(ofSize: 13)
        body.frame = NSRect(x: 24, y: 96, width: 472, height: 192)
        container.addSubview(body)

        let openButton = NSButton(title: "Open System Settings", target: self, action: #selector(openSettings))
        openButton.bezelStyle = .rounded
        openButton.frame = NSRect(x: 24, y: 24, width: 220, height: 32)
        container.addSubview(openButton)

        let quitButton = NSButton(title: "Quit & Reopen", target: self, action: #selector(quit))
        quitButton.bezelStyle = .rounded
        quitButton.frame = NSRect(x: 264, y: 24, width: 232, height: 32)
        container.addSubview(quitButton)

        return container
    }

    @objc private func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }
}

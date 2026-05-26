import AppKit
import SwiftUI

/// Hosts `LayoutEditorView` in a standalone window. Mirrors the
/// `OnboardingWindow` pattern (NSWindowController owning an NSWindow);
/// the SwiftUI root is wrapped in NSHostingView.
final class LayoutEditorWindow: NSWindowController, NSWindowDelegate {
    private let model: LayoutEditorModel

    init(model: LayoutEditorModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mullion Layout Editor"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1040, height: 640)
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: LayoutEditorView(model: model))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard unsaved changes?"
        alert.informativeText = "You have unsaved edits to this layout. Closing will lose them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save & Close")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            model.save()
            return true
        case .alertSecondButtonReturn:
            model.revert()
            return true
        default:
            return false
        }
    }
}

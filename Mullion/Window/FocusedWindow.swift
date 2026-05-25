import AppKit
import ApplicationServices

enum FocusedWindow {
    static func current() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef,
              CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        return AXWindow(element: window as! AXUIElement, pid: pid)  // safe: CFGetTypeID == AXUIElementGetTypeID() checked above
    }
}

import AppKit
import ApplicationServices

/// Thin read-only wrapper over `AXUIElement`. Mutation goes through
/// `WindowMutator`; this type only exposes what callers read.
struct AXWindow {
    let element: AXUIElement
    let pid: pid_t

    var title: String? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        return value as? String
    }

    /// Window frame in AX (top-left global) coordinates.
    var axFrame: CGRect? {
        guard let position = readPosition(), let size = readSize() else { return nil }
        return CGRect(origin: position, size: size)
    }

    var isFullscreen: Bool {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &value)
        return (value as? Bool) ?? false
    }

    var bundleIdentifier: String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    private func readPosition() -> CGPoint? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let raw = value,
              CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        let axValue = raw as! AXValue
        var point = CGPoint.zero
        AXValueGetValue(axValue, .cgPoint, &point)
        return point
    }

    private func readSize() -> CGSize? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let raw = value,
              CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        let axValue = raw as! AXValue
        var size = CGSize.zero
        AXValueGetValue(axValue, .cgSize, &size)
        return size
    }
}

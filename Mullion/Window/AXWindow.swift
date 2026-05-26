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

    /// Hit-test the AX tree at `axPoint` (top-left global coords, matching
    /// `CGEvent.location`) and walk parents until we land on the enclosing
    /// window. Used by `DragOverlayController` to capture the window under
    /// the cursor at mouse-down — `FocusedWindow.current()` is racy because
    /// `CGEventTap` fires before macOS finishes processing the click's
    /// focus transfer.
    static func atScreenPoint(_ axPoint: CGPoint) -> AXWindow? {
        let systemWide = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(axPoint.x),
            Float(axPoint.y),
            &hit
        )
        guard status == .success, var element = hit else { return nil }
        // Walk up; cap depth so a degenerate tree can't spin us forever.
        for _ in 0..<16 {
            var roleRef: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == (kAXWindowRole as String) {
                var pid: pid_t = 0
                guard AXUIElementGetPid(element, &pid) == .success else { return nil }
                return AXWindow(element: element, pid: pid)
            }
            var parentRef: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parent = parentRef,
                  CFGetTypeID(parent) == AXUIElementGetTypeID()
            else { return nil }
            element = parent as! AXUIElement  // safe: CFGetTypeID == AXUIElementGetTypeID() checked above
        }
        return nil
    }

    private func readPosition() -> CGPoint? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let raw = value,
              CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        let axValue = raw as! AXValue  // safe: CFGetTypeID == AXValueGetTypeID() checked above
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
        let axValue = raw as! AXValue  // safe: CFGetTypeID == AXValueGetTypeID() checked above
        var size = CGSize.zero
        AXValueGetValue(axValue, .cgSize, &size)
        return size
    }
}

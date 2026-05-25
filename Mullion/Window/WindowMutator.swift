import ApplicationServices
import CoreGraphics

/// Sole path for mutating window position/size. Implements:
///   1. size → position → size dance (defeats macOS's clamping when crossing
///      displays: the first size fits the window to the target display, the
///      position moves it, the final size restores any dimension clamped earlier).
///   2. AXEnhancedUserInterface toggle (Office/Electron apps animate every
///      mutation while EUI is on; toggling it off during the write makes
///      frames land cleanly).
///   3. Native-fullscreen exit (fullscreen windows silently ignore position/size).
enum WindowMutator {
    @discardableResult
    static func set(_ window: AXWindow, axFrame frame: CGRect) -> CGRect? {
        let appElement = AXUIElementCreateApplication(window.pid)
        let hadEnhancedUI = readEnhancedUI(appElement)

        if hadEnhancedUI {
            setEnhancedUI(appElement, enabled: false)
        }
        defer {
            if hadEnhancedUI {
                setEnhancedUI(appElement, enabled: true)
            }
        }

        if window.isFullscreen {
            AXUIElementSetAttributeValue(window.element, "AXFullScreen" as CFString, kCFBooleanFalse)
        }

        write(window.element, size: frame.size)
        write(window.element, position: frame.origin)
        write(window.element, size: frame.size)

        return window.axFrame
    }

    private static func write(_ element: AXUIElement, position: CGPoint) {
        var value = position
        guard let axValue = AXValueCreate(.cgPoint, &value) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axValue)
    }

    private static func write(_ element: AXUIElement, size: CGSize) {
        var value = size
        guard let axValue = AXValueCreate(.cgSize, &value) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axValue)
    }

    private static let enhancedUIAttribute = "AXEnhancedUserInterface" as CFString

    private static func readEnhancedUI(_ appElement: AXUIElement) -> Bool {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(appElement, enhancedUIAttribute, &value)
        return (value as? Bool) ?? false
    }

    private static func setEnhancedUI(_ appElement: AXUIElement, enabled: Bool) {
        AXUIElementSetAttributeValue(
            appElement,
            enhancedUIAttribute,
            (enabled ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef
        )
    }
}

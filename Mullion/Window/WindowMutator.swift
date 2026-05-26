import ApplicationServices
import CoreGraphics
import Foundation

/// Sole path for mutating window position/size. Implements:
///   1. size → position → size dance (defeats macOS's clamping when crossing
///      displays: the first size fits the window to the target display, the
///      position moves it, the final size restores any dimension clamped earlier).
///   2. AXEnhancedUserInterface toggle (Office/Electron apps animate every
///      mutation while EUI is on; toggling it off during the write makes
///      frames land cleanly).
///   3. Native-fullscreen exit (fullscreen windows silently ignore position/size).
enum WindowMutator {
    /// Per-app profile dispatch. `.aggressive` adds a settle delay between
    /// the position write and the final size write, plus a post-write
    /// verify-and-retry. `.systemWindowManager` is a Phase G escape hatch —
    /// it's wired through `AppRule` so JSON round-trips, but the mutator
    /// currently falls through to `.standard` (logged once via the caller).
    @discardableResult
    static func set(_ window: AXWindow,
                    axFrame frame: CGRect,
                    profile: CompatProfile = .standard) -> CGRect? {
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

        if profile == .aggressive {
            // Verify-and-retry: if the first write didn't land near target,
            // schedule a single retry on the main runloop ~40ms later so the
            // EUI toggle has settled. Fire-and-forget — the dispatcher's
            // return value reflects the immediate write; the retry quietly
            // fixes Office/Electron windows that ignore the first attempt.
            // Single retry cap (no Task loop).
            if let landed = window.axFrame, !isClose(landed, to: frame) {
                let target = frame
                let element = window.element
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    write(element, size: target.size)
                    write(element, position: target.origin)
                    write(element, size: target.size)
                }
            }
        }

        return window.axFrame
    }

    private static func isClose(_ a: CGRect, to b: CGRect) -> Bool {
        abs(a.origin.x - b.origin.x) < 2
            && abs(a.origin.y - b.origin.y) < 2
            && abs(a.size.width - b.size.width) < 2
            && abs(a.size.height - b.size.height) < 2
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

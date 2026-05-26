import AppKit

/// Single conversion site between AppKit (bottom-left origin, primary-screen
/// anchored) and AX (top-left origin, global). Every multi-display bug in a
/// Mac window manager comes from doing this math at call sites — keep it here.
enum Geometry {
    /// The screen whose AppKit origin is (0, 0). This is the anchor for
    /// AppKit↔AX conversion. NOT `NSScreen.main` — that's the key window's
    /// screen, which can be any of the connected displays.
    static var originScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero }
    }

    /// Convert an AppKit rect (bottom-left origin) to AX coordinates
    /// (top-left, global). Returns nil if no displays are connected.
    static func appKitToAX(_ rect: CGRect) -> CGRect? {
        guard let origin = originScreen else { return nil }
        return flipY(rect, originScreenMaxY: origin.frame.maxY)
    }

    /// AX → AppKit. Symmetric with `appKitToAX`.
    static func axToAppKit(_ rect: CGRect) -> CGRect? {
        guard let origin = originScreen else { return nil }
        return flipY(rect, originScreenMaxY: origin.frame.maxY)
    }

    /// Point form of `axToAppKit` — convenience for cursor positions where
    /// only an origin is meaningful. Same y-flip pivot as the rect variant.
    static func axToAppKitPoint(_ point: CGPoint) -> CGPoint? {
        guard let origin = originScreen else { return nil }
        return CGPoint(x: point.x, y: origin.frame.maxY - point.y)
    }

    /// Reverse of `axToAppKitPoint`. Used when reading `NSEvent.mouseLocation`
    /// (AppKit space) and we need to hit-test against AX (Quartz) coords.
    static func appKitToAXPoint(_ point: CGPoint) -> CGPoint? {
        guard let origin = originScreen else { return nil }
        return CGPoint(x: point.x, y: origin.frame.maxY - point.y)
    }

    /// Pure math entry point for testing — doesn't depend on NSScreen.
    /// The flip is symmetric, so it's the same transform either direction.
    static func flipY(_ rect: CGRect, originScreenMaxY: CGFloat) -> CGRect {
        let flippedY = originScreenMaxY - (rect.origin.y + rect.size.height)
        return CGRect(x: rect.origin.x, y: flippedY, width: rect.size.width, height: rect.size.height)
    }

    /// Find the NSScreen with the largest intersection with the given
    /// AppKit-space rect. Used for "which display is this window on?".
    static func screen(containingAppKitRect rect: CGRect) -> NSScreen? {
        var best: (screen: NSScreen, area: CGFloat)?
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(rect)
            if intersection.isNull { continue }
            let area = intersection.width * intersection.height
            if best == nil || area > best!.area {
                best = (screen, area)
            }
        }
        return best?.screen ?? NSScreen.main
    }

    /// Largest-intersection lookup over an arbitrary list of screen frames.
    /// Testable entry point; production code calls the NSScreen variant.
    static func indexOfScreen(containingAppKitRect rect: CGRect, in screenFrames: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (idx, frame) in screenFrames.enumerated() {
            let intersection = frame.intersection(rect)
            if intersection.isNull { continue }
            let area = intersection.width * intersection.height
            if best == nil || area > best!.area {
                best = (idx, area)
            }
        }
        return best?.index
    }
}

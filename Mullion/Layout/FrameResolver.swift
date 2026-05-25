import AppKit

/// Zone × display → AppKit-space CGRect. The output is in AppKit
/// coordinates (bottom-left origin). Use `Geometry.appKitToAX` to convert
/// before handing to `WindowMutator`.
enum FrameResolver {
    static func appKitFrame(for zone: Zone, on screen: NSScreen) -> CGRect {
        appKitFrame(for: zone, in: screen.visibleFrame)
    }

    /// Pure-math entry point for testing — takes the visible frame directly
    /// so callers don't need a real NSScreen.
    static func appKitFrame(for zone: Zone, in visibleFrame: CGRect) -> CGRect {
        // Zone uses y=0 at top. visibleFrame has y=0 at bottom. Flip:
        let appKitX = visibleFrame.origin.x + zone.x * visibleFrame.size.width
        let appKitY = visibleFrame.origin.y + (1 - zone.y - zone.height) * visibleFrame.size.height
        let appKitWidth = zone.width * visibleFrame.size.width
        let appKitHeight = zone.height * visibleFrame.size.height
        let zoneRect = CGRect(x: appKitX, y: appKitY, width: appKitWidth, height: appKitHeight)

        guard let override = zone.sizeOverride else { return zoneRect }
        return anchored(
            size: CGSize(width: override.width, height: override.height),
            within: zoneRect,
            anchor: zone.anchor
        )
    }

    private static func anchored(size: CGSize, within frame: CGRect, anchor: Anchor) -> CGRect {
        let x: CGFloat
        let y: CGFloat
        switch anchor {
        case .topLeft, .left, .bottomLeft:
            x = frame.origin.x
        case .top, .center, .bottom:
            x = frame.origin.x + (frame.size.width - size.width) / 2
        case .topRight, .right, .bottomRight:
            x = frame.origin.x + frame.size.width - size.width
        }
        // AppKit y: high = top of screen.
        switch anchor {
        case .topLeft, .top, .topRight:
            y = frame.origin.y + frame.size.height - size.height
        case .left, .center, .right:
            y = frame.origin.y + (frame.size.height - size.height) / 2
        case .bottomLeft, .bottom, .bottomRight:
            y = frame.origin.y
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

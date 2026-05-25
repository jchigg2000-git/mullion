import AppKit

/// Zone × display → AppKit-space CGRect. The output is in AppKit
/// coordinates (bottom-left origin). Use `Geometry.appKitToAX` to convert
/// before handing to `WindowMutator`.
enum FrameResolver {
    /// Production entry point: applies `outerMargin` and `innerGap` from the
    /// zone's parent layout. Pass `layout = nil` for an "anonymous" zone with
    /// no margins.
    static func appKitFrame(for zone: Zone, in layout: Layout?, on screen: NSScreen) -> CGRect {
        appKitFrame(
            for: zone,
            in: screen.visibleFrame,
            outerMargin: layout?.outerMargin ?? .zero,
            innerGap: layout?.innerGap ?? 0
        )
    }

    static func appKitFrame(for zone: Zone, on screen: NSScreen) -> CGRect {
        appKitFrame(for: zone, in: screen.visibleFrame)
    }

    /// Pure-math entry point for testing — takes the visible frame directly
    /// so callers don't need a real NSScreen. Margins and gap default to zero
    /// so existing tests pass unchanged.
    static func appKitFrame(for zone: Zone,
                            in visibleFrame: CGRect,
                            outerMargin: LayoutInsets = .zero,
                            innerGap: Double = 0) -> CGRect {
        let usable = applyOuterMargin(visibleFrame, outerMargin)

        // Zone uses y=0 at top. AppKit has y=0 at bottom. Flip:
        let appKitX = usable.origin.x + zone.x * usable.size.width
        let appKitY = usable.origin.y + (1 - zone.y - zone.height) * usable.size.height
        let appKitWidth = zone.width * usable.size.width
        let appKitHeight = zone.height * usable.size.height
        var zoneRect = CGRect(x: appKitX, y: appKitY, width: appKitWidth, height: appKitHeight)

        if innerGap > 0 {
            zoneRect = applyInnerGap(zoneRect, gap: innerGap, zone: zone)
        }

        guard let override = zone.sizeOverride else { return zoneRect }
        return anchored(
            size: CGSize(width: override.width, height: override.height),
            within: zoneRect,
            anchor: zone.anchor
        )
    }

    // MARK: Internals

    /// Outer margin shrinks the visible frame. Top/bottom map to AppKit y
    /// the same way zones do: `top` reduces the upper edge (higher AppKit y),
    /// `bottom` reduces the lower edge (lower AppKit y).
    private static func applyOuterMargin(_ frame: CGRect, _ insets: LayoutInsets) -> CGRect {
        guard !insets.isZero else { return frame }
        let x = frame.origin.x + insets.leading
        let y = frame.origin.y + insets.bottom
        let w = max(0, frame.size.width - insets.leading - insets.trailing)
        let h = max(0, frame.size.height - insets.top - insets.bottom)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Shrink the zone rect by `gap / 2` on each interior side — edges that
    /// touch the layout boundary (zone coords at 0 or 1) are left alone so
    /// outer spacing comes only from `outerMargin`.
    private static func applyInnerGap(_ rect: CGRect, gap: Double, zone: Zone) -> CGRect {
        let half = gap / 2
        let epsilon = 0.001
        // Zone-space edge flags (top = y, bottom = y+h, left = x, right = x+w).
        let leftIsBoundary = zone.x <= epsilon
        let rightIsBoundary = (zone.x + zone.width) >= 1 - epsilon
        let topIsBoundary = zone.y <= epsilon
        let bottomIsBoundary = (zone.y + zone.height) >= 1 - epsilon
        // AppKit y is flipped relative to zone y: zone's "top" maps to the
        // upper side in AppKit (higher y), zone's "bottom" to the lower side.
        let leftInset: Double = leftIsBoundary ? 0 : half
        let rightInset: Double = rightIsBoundary ? 0 : half
        let appKitUpperInset: Double = topIsBoundary ? 0 : half        // shrinks rect.maxY
        let appKitLowerInset: Double = bottomIsBoundary ? 0 : half      // shrinks rect.minY
        let x = rect.origin.x + leftInset
        let y = rect.origin.y + appKitLowerInset
        let w = max(0, rect.size.width - leftInset - rightInset)
        let h = max(0, rect.size.height - appKitUpperInset - appKitLowerInset)
        return CGRect(x: x, y: y, width: w, height: h)
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

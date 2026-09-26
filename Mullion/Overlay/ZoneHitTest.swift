import AppKit

/// Cursor → zone resolution shared by the drag and grid overlays. Reads
/// `NSScreen.screens` live on every call, so a display reconfiguration
/// (dock/undock, primary change, resolution change) can never leave it
/// resolving against geometry captured before the change.
@MainActor
enum ZoneHitTest {
    struct Hit {
        let zone: Zone
        let layout: Layout
        let screen: NSScreen
    }

    /// `axPoint` is in Quartz global space (top-left origin) — the space
    /// `MouseEventTap` delivers. `layoutFor` picks the governing layout for
    /// a screen; callers pass their own so both overlays share one policy.
    static func resolve(axPoint: CGPoint, layoutFor: (NSScreen) -> Layout?) -> Hit? {
        guard let appKitPoint = Geometry.axToAppKitPoint(axPoint),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitPoint) }),
              let layout = layoutFor(screen),
              let index = zoneIndex(at: appKitPoint, in: layout, visibleFrame: screen.visibleFrame)
        else { return nil }
        return Hit(zone: layout.zones[index], layout: layout, screen: screen)
    }

    /// Pure-math entry point for testing — takes the screen's current
    /// visible frame directly so callers don't need a real NSScreen. Uses
    /// the same `FrameResolver` math the overlays render with, so the zone
    /// under the cursor is always the zone drawn under the cursor.
    nonisolated static func zoneIndex(at appKitPoint: CGPoint,
                                      in layout: Layout,
                                      visibleFrame: CGRect) -> Int? {
        layout.zones.firstIndex { zone in
            FrameResolver.appKitFrame(
                for: zone,
                in: visibleFrame,
                outerMargin: layout.outerMargin,
                innerGap: layout.innerGap
            ).contains(appKitPoint)
        }
    }
}

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
    /// `preferTopmost` — see `zoneIndex(at:in:visibleFrame:preferTopmost:)`.
    static func resolve(axPoint: CGPoint,
                        preferTopmost: Bool = false,
                        layoutFor: (NSScreen) -> Layout?) -> Hit? {
        guard let appKitPoint = Geometry.axToAppKitPoint(axPoint),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitPoint) }),
              let layout = layoutFor(screen),
              let index = zoneIndex(at: appKitPoint,
                                    in: layout,
                                    visibleFrame: screen.visibleFrame,
                                    preferTopmost: preferTopmost)
        else { return nil }
        return Hit(zone: layout.zones[index], layout: layout, screen: screen)
    }

    /// Pure-math entry point for testing — takes the screen's current
    /// visible frame directly so callers don't need a real NSScreen. Uses
    /// the same `FrameResolver` math the overlays render with.
    ///
    /// Zones may overlap (a full-screen zone listed before quadrants). The
    /// overlays paint zones in array order, so the last zone containing the
    /// point is the one drawn on top. `preferTopmost` picks that one — the
    /// grid needs it so a click lands on the zone the user sees, as its old
    /// per-zone tap targets did. Without it the first match wins, which is
    /// drag-to-snap's long-standing hover rule (drag highlights its hover
    /// by id, so what it shows always matches what it snaps).
    nonisolated static func zoneIndex(at appKitPoint: CGPoint,
                                      in layout: Layout,
                                      visibleFrame: CGRect,
                                      preferTopmost: Bool = false) -> Int? {
        let contains: (Zone) -> Bool = { zone in
            FrameResolver.appKitFrame(
                for: zone,
                in: visibleFrame,
                outerMargin: layout.outerMargin,
                innerGap: layout.innerGap
            ).contains(appKitPoint)
        }
        return preferTopmost
            ? layout.zones.lastIndex(where: contains)
            : layout.zones.firstIndex(where: contains)
    }
}

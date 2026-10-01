import AppKit
import SwiftUI
import os

/// Hold-modifier grid overlay for Phase E step #26.
///
/// While the user holds the configured modifier (default ⌃⌥), each display
/// reveals an `NSPanel` painting every zone in its matching layout with a
/// large number badge in the centre. The badge mirrors the existing
/// `⌥⌃<n>` snap-by-index binding (zone[0] → "1" → key ⌥⌃1 …
/// zone[9] → "0" → key ⌥⌃0), so the same gesture works two ways:
///
///   - Hotkey: hold ⌃⌥, press the digit → existing `ActionDispatcher`
///     `snapByIndex` path fires. The grid is purely visual here.
///   - Click: hold ⌃⌥, click a zone → this controller snaps the
///     captured-at-reveal focused window into that zone.
///
/// Modifier release (`onFlagsChanged`) hides the grid. Clicks are resolved
/// from `MouseEventTap`'s mouse-down against live screen geometry
/// (`ZoneHitTest`), the same way drag-to-snap resolves its hover. The
/// non-activating panels only paint the zones and swallow the click so it
/// never reaches the app underneath (where ⌃⌥-click would open a context
/// menu). They used to hit-test the click themselves, which broke silently
/// whenever a cached panel's frame or screen went stale.
@MainActor
final class GridOverlayController {
    private let log = Logger(subsystem: "com.mullion.Mullion", category: "grid-overlay")
    private let layoutStore: LayoutStore
    private let settingsStore: SettingsStore
    private let appRuleStore: AppRuleStore
    private let recorder: SnapRecorder
    private let mover: any WindowMover

    private enum State {
        case idle
        /// `focused` snapshotted at reveal time — clicking the grid snaps
        /// *that* window, not whatever happens to be focused at click time.
        /// Avoids races where focus might shift between reveal and click.
        case visible(focused: AXWindow?)
    }

    private var state: State = .idle
    private var overlays: [String: GridOverlayPanel] = [:]
    private let tintProvider = WallpaperTintProvider()

    init(layoutStore: LayoutStore,
         settingsStore: SettingsStore,
         appRuleStore: AppRuleStore,
         historyStore: WindowHistoryStore,
         focusIndex: FocusIndex? = nil,
         mover: any WindowMover = ChainedWindowMover.default) {
        self.layoutStore = layoutStore
        self.settingsStore = settingsStore
        self.appRuleStore = appRuleStore
        self.recorder = SnapRecorder(history: historyStore, focusIndex: focusIndex)
        self.mover = mover
    }

    // MARK: - Event tap callback

    func handleFlagsChanged(_ flags: CGEventFlags) {
        let active = settingsStore.settings.gridModifier.isSatisfied(by: flags)
        switch (active, state) {
        case (true, .idle):
            let focused = FocusedWindow.current()
            state = .visible(focused: focused)
            showOverlays()
            log.notice("grid revealed (focused: \(focused?.bundleIdentifier ?? "—", privacy: .public))")
        case (false, .visible):
            state = .idle
            hideOverlays()
        default:
            break
        }
    }

    /// Grid clicks arrive here from the event tap, not from the panels.
    /// Every early return logs at `.notice` so a click that snaps nothing
    /// is distinguishable in the log from a click that never arrived.
    func handleMouseDown(at axPoint: CGPoint, flags: CGEventFlags) {
        guard case .visible(let focused) = state else { return }
        // A modifier release lost while the tap was disabled (main-thread
        // stall past the tap timeout) leaves the grid armed; an unmodified
        // click must dismiss it, not snap the window captured at reveal.
        guard settingsStore.settings.gridModifier.isSatisfied(by: flags) else {
            state = .idle
            hideOverlays()
            log.notice("grid click without grid modifier — grid dismissed, no snap")
            return
        }
        guard let hit = ZoneHitTest.resolve(axPoint: axPoint,
                                            preferTopmost: true,
                                            layoutFor: layoutForScreen) else {
            log.notice("grid click outside any zone @ (\(Int(axPoint.x), privacy: .public), \(Int(axPoint.y), privacy: .public)) — no snap")
            return
        }
        guard let window = focused ?? FocusedWindow.current() else {
            log.notice("grid tap with no focused window — no snap")
            return
        }
        snapWindow(window, to: hit.zone, layout: hit.layout, screen: hit.screen)
    }

    // MARK: - Snap

    private func snapWindow(_ window: AXWindow, to zone: Zone, layout: Layout, screen: NSScreen) {
        let targetAppKit = FrameResolver.appKitFrame(for: zone, in: layout, on: screen)
        guard let targetAX = Geometry.appKitToAX(targetAppKit) else {
            log.error("grid-snap: AppKit→AX conversion failed")
            return
        }
        // Same rationale as drag-snap: force `.aggressive` so the verify-
        // and-retry path covers any post-write reordering from macOS.
        let profile: CompatProfile = .aggressive
        let landed = mover.move(window, to: targetAX, profile: profile)
        if !landed {
            log.notice("grid-snap did not land near target zone=\(zone.name, privacy: .public)")
        }
        recorder.record(
            window: window,
            bundleID: window.bundleIdentifier,
            screenUUID: DisplayRegistry.uuid(for: screen),
            zoneID: zone.id
        )
        log.notice("grid-snap → '\(zone.name, privacy: .public)' on '\(screen.localizedName, privacy: .public)'")
    }

    // MARK: - Helpers

    private func layoutForScreen(_ screen: NSScreen) -> Layout? {
        let uuid = DisplayRegistry.uuid(for: screen)
        let aspect = Double(screen.frame.width / screen.frame.height)
        return layoutStore.layout(forScreenUUID: uuid, aspectRatio: aspect)
    }

    private func showOverlays() {
        for screen in NSScreen.screens {
            guard let layout = layoutForScreen(screen) else { continue }
            let uuid = DisplayRegistry.uuid(for: screen)
            let panel = overlays[uuid] ?? GridOverlayPanel(screen: screen)
            overlays[uuid] = panel
            let tint = Color(nsColor: tintProvider.tint(for: screen))
            panel.render(screen: screen, layout: layout, tint: tint)
            panel.show()
        }
    }

    private func hideOverlays() {
        for panel in overlays.values {
            panel.hide()
        }
    }
}

// MARK: - Per-display panel

/// Non-activating `NSPanel` covering a single display. Accepts clicks
/// (unlike the drag overlay's click-through window) only to swallow them —
/// the controller resolves the zone from the event tap. `.nonactivatingPanel`
/// prevents the click from stealing focus from the user's actual window.
@MainActor
private final class GridOverlayPanel {
    private let panel: NSPanel
    private let hosting: NSHostingView<GridContentView>

    init(screen: NSScreen) {
        let initial = GridContentView(zones: [], tint: .accentColor)
        let view = NSHostingView(rootView: initial)
        self.hosting = view

        let p = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        p.contentView = view
        // The `screen:` init argument is a hint; force placement explicitly
        // so multi-display setups don't end up with every panel invisibly
        // stacked on the primary screen. See DragOverlayController's
        // OverlayWindow for the matching fix.
        p.setFrame(screen.frame, display: false)
        self.panel = p
    }

    func render(screen: NSScreen, layout: Layout, tint: Color) {
        // Panels are cached per display UUID for the app's lifetime, but a
        // display keeps its UUID while its frame moves (dock/undock, primary
        // change, resolution change). Re-place on every render so the zones
        // are painted where they now are, not where the display used to be.
        if panel.frame != screen.frame {
            panel.setFrame(screen.frame, display: false)
        }
        var rendered: [GridContentView.RenderZone] = []
        rendered.reserveCapacity(layout.zones.count)
        for (idx, zone) in layout.zones.enumerated() {
            let appKit = FrameResolver.appKitFrame(for: zone, in: layout, on: screen)
            let localX = appKit.minX - screen.frame.minX
            let localBottomY = appKit.minY - screen.frame.minY
            let topY = screen.frame.height - (localBottomY + appKit.height)
            // Mirror `HotkeyManager.indexedNames` numbering: zones 0-8 → "1"-"9",
            // zone 9 → "0". Zones beyond index 10 have no `⌥⌃<n>` binding and
            // render without a badge (still clickable).
            let badge: String?
            switch idx {
            case 0..<9: badge = String(idx + 1)
            case 9: badge = "0"
            default: badge = nil
            }
            rendered.append(.init(
                id: zone.id,
                badge: badge,
                frame: CGRect(x: localX, y: topY, width: appKit.width, height: appKit.height)
            ))
        }
        hosting.rootView = GridContentView(zones: rendered, tint: tint)
    }

    func show() {
        panel.orderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }
}

// MARK: - SwiftUI content

private struct GridContentView: View {
    struct RenderZone: Identifiable {
        let id: UUID
        let badge: String?
        let frame: CGRect
    }

    let zones: [RenderZone]
    let tint: Color

    var body: some View {
        GeometryReader { _ in
            ForEach(zones) { zone in
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tint.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(tint, lineWidth: 3)
                        )
                    if let badge = zone.badge {
                        Text(badge)
                            .font(.system(size: badgeFontSize(for: zone.frame), weight: .bold, design: .rounded))
                            .foregroundColor(tint)
                            .shadow(color: .black.opacity(0.35), radius: 6)
                    }
                }
                .frame(width: zone.frame.size.width, height: zone.frame.size.height)
                .position(
                    x: zone.frame.origin.x + zone.frame.size.width / 2,
                    y: zone.frame.origin.y + zone.frame.size.height / 2
                )
            }
        }
        .ignoresSafeArea()
    }

    /// Badge ≈ 25% of the zone's shorter side, clamped to a readable range.
    /// A 1920×1080 zone gets ~270pt (capped at 180); a 400×200 zone gets
    /// ~50pt (floored at 40).
    private func badgeFontSize(for frame: CGRect) -> CGFloat {
        let dim = min(frame.size.width, frame.size.height)
        return max(40, min(180, dim * 0.25))
    }
}

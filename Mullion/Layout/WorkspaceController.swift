import AppKit
import ApplicationServices
import os

/// Capture + restore engine for `Workspace`. Lives outside `WorkspaceStore`
/// so Phase F #28 (arrangement-bound auto-restore) can drive it from
/// `AppDelegate` without going through the editor model.
@MainActor
final class WorkspaceController {
    private let log = Logger(subsystem: "com.mullion.Mullion", category: "workspace")
    private let layoutStore: LayoutStore
    private let workspaceStore: WorkspaceStore
    private let appRuleStore: AppRuleStore
    private let mover: any WindowMover

    init(layoutStore: LayoutStore,
         workspaceStore: WorkspaceStore,
         appRuleStore: AppRuleStore,
         mover: any WindowMover = ChainedWindowMover.default) {
        self.layoutStore = layoutStore
        self.workspaceStore = workspaceStore
        self.appRuleStore = appRuleStore
        self.mover = mover
    }

    // MARK: Capture

    /// Snapshot every regular running app's windows. A window contributes an
    /// item when its centre lands inside some zone's computed AppKit rect on
    /// its display. Loose windows (centre outside every zone) are skipped —
    /// `LearnedPlacement` already owns that responsibility; a workspace is a
    /// zone snapshot, not a free-frame snapshot.
    func captureCurrent(name: String) -> Workspace {
        var items: [WorkspaceItem] = []
        for runningApp in NSWorkspace.shared.runningApplications {
            guard runningApp.activationPolicy == .regular,
                  let bundleID = runningApp.bundleIdentifier else { continue }

            let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
            var windowsRef: AnyObject?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else { continue }

            for window in windows {
                let ax = AXWindow(element: window, pid: runningApp.processIdentifier)
                guard !ax.isFullscreen,
                      let axFrame = ax.axFrame,
                      let appKitFrame = Geometry.axToAppKit(axFrame),
                      let screen = Geometry.screen(containingAppKitRect: appKitFrame) else { continue }

                let centre = CGPoint(x: appKitFrame.midX, y: appKitFrame.midY)
                guard let zoneID = zoneContaining(point: centre, on: screen) else { continue }

                items.append(WorkspaceItem(
                    bundleID: bundleID,
                    windowTitle: ax.title,
                    capturedAXFrame: axFrame,
                    displayUUID: DisplayRegistry.uuid(for: screen),
                    zoneID: zoneID
                ))
            }
        }
        let workspace = Workspace(name: name, items: items)
        workspaceStore.upsert(workspace)
        log.notice("captured workspace '\(name, privacy: .public)' with \(items.count, privacy: .public) item(s)")
        return workspace
    }

    /// First zone (across all layouts) whose computed AppKit rect on `screen`
    /// contains `point`. Layout iteration order matches `LayoutStore.layouts`
    /// — the same first-match semantics ⌥⌃<n> resolution uses.
    private func zoneContaining(point: CGPoint, on screen: NSScreen) -> UUID? {
        let uuid = DisplayRegistry.uuid(for: screen)
        let aspect = Double(screen.frame.width / screen.frame.height)
        for layout in layoutStore.layouts {
            guard layout.displayPredicate.matches(uuid: uuid, aspectRatio: aspect) else { continue }
            for zone in layout.zones {
                let rect = FrameResolver.appKitFrame(for: zone, in: layout, on: screen)
                if rect.contains(point) { return zone.id }
            }
        }
        return nil
    }

    // MARK: Restore

    /// Apply every item in `workspace` whose target display is still
    /// connected. Items whose `displayUUID` isn't currently attached are
    /// skipped silently — a future invocation under the right arrangement
    /// will pick them up.
    ///
    /// Match strategy per item: find the first running window for `bundleID`
    /// that isn't already inside the target zone. This avoids stomping the
    /// other windows of a multi-window app on re-runs of the same workspace.
    /// If every window of the app is already placed, the item is a no-op.
    @discardableResult
    func restore(_ workspace: Workspace) -> Int {
        var applied = 0
        // Group items by bundleID so we can fan out to multiple windows of
        // the same app in a single pass instead of re-enumerating per item.
        let byBundle = Dictionary(grouping: workspace.items, by: \.bundleID)
        for (bundleID, items) in byBundle {
            guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == bundleID
            }) else { continue }

            let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
            var windowsRef: AnyObject?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else { continue }

            var available = windows.map { AXWindow(element: $0, pid: runningApp.processIdentifier) }
            for item in items {
                guard let screen = DisplayRegistry.shared.screen(forUUID: item.displayUUID),
                      let zone = layoutStore.zone(withID: item.zoneID) else { continue }
                let layout = layoutStore.layout(containingZoneID: item.zoneID)
                let targetAppKit = FrameResolver.appKitFrame(for: zone, in: layout, on: screen)
                guard let targetAX = Geometry.appKitToAX(targetAppKit) else { continue }

                // Window selection priority. Apps with multiple windows (esp.
                // iTerm, Finder) often title every window the same string, so
                // captured frame is the most reliable per-window identifier.
                //   1. closest by Euclidean distance to `capturedAXFrame` —
                //      handles same-titled multi-window apps as long as the
                //      windows were at distinct positions at capture time.
                //   2. exact `windowTitle` match — used when capturedFrame is
                //      absent (workspaces.json from an older Mullion build).
                //   3. first remaining window — last resort.
                let pickIdx: Int? = {
                    if let captured = item.capturedAXFrame {
                        var bestIdx: Int?
                        var bestDist: CGFloat = .infinity
                        for (i, ax) in available.enumerated() {
                            guard let f = ax.axFrame else { continue }
                            let dx = f.origin.x - captured.origin.x
                            let dy = f.origin.y - captured.origin.y
                            let dist = dx * dx + dy * dy
                            if dist < bestDist {
                                bestDist = dist
                                bestIdx = i
                            }
                        }
                        if let bestIdx { return bestIdx }
                    }
                    if let title = item.windowTitle, !title.isEmpty,
                       let idx = available.firstIndex(where: { $0.title == title }) {
                        return idx
                    }
                    return available.indices.first
                }()
                guard let idx = pickIdx else { continue }
                let target = available.remove(at: idx)

                let profile = appRuleStore.profile(forBundleID: bundleID, on: screen)
                if mover.move(target, to: targetAX, profile: profile) {
                    applied += 1
                } else {
                    log.debug("restore did not land near target for \(bundleID, privacy: .public) zone=\(zone.name, privacy: .public)")
                }
            }
        }
        log.notice("restored workspace '\(workspace.name, privacy: .public)': \(applied, privacy: .public)/\(workspace.items.count, privacy: .public) item(s) applied")
        return applied
    }
}

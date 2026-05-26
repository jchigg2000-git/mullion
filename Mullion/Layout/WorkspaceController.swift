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
        let restoreID = String(UUID().uuidString.prefix(8))
        log.notice("restore-begin id=\(restoreID, privacy: .public) workspace='\(workspace.name, privacy: .public)' items=\(workspace.items.count, privacy: .public)")
        var applied = 0
        // Group items by bundleID so we can fan out to multiple windows of
        // the same app in a single pass instead of re-enumerating per item.
        let byBundle = Dictionary(grouping: workspace.items, by: \.bundleID)
        for (bundleID, items) in byBundle {
            guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == bundleID
            }) else {
                log.notice("restore-skip id=\(restoreID, privacy: .public) bundle=\(bundleID, privacy: .public) reason=app-not-running items=\(items.count, privacy: .public)")
                continue
            }

            let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
            var windowsRef: AnyObject?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else {
                log.notice("restore-skip id=\(restoreID, privacy: .public) bundle=\(bundleID, privacy: .public) reason=ax-windows-fetch-failed")
                continue
            }
            log.notice("restore-bundle id=\(restoreID, privacy: .public) bundle=\(bundleID, privacy: .public) availableWindows=\(windows.count, privacy: .public) items=\(items.count, privacy: .public)")

            var available = windows.map { AXWindow(element: $0, pid: runningApp.processIdentifier) }
            for item in items {
                guard let screen = DisplayRegistry.shared.screen(forUUID: item.displayUUID),
                      let zone = layoutStore.zone(withID: item.zoneID) else {
                    log.notice("restore-skip-item id=\(restoreID, privacy: .public) bundle=\(bundleID, privacy: .public) reason=display-or-zone-missing displayUUID=\(item.displayUUID, privacy: .public)")
                    continue
                }
                let layout = layoutStore.layout(containingZoneID: item.zoneID)
                let targetAppKit = FrameResolver.appKitFrame(for: zone, in: layout, on: screen)
                guard let targetAX = Geometry.appKitToAX(targetAppKit) else {
                    log.notice("restore-skip-item id=\(restoreID, privacy: .public) bundle=\(bundleID, privacy: .public) zone=\(zone.name, privacy: .public) reason=geometry-conversion-failed")
                    continue
                }

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
                guard let idx = pickIdx else {
                    log.notice("restore-skip-item id=\(restoreID, privacy: .public) bundle=\(bundleID, privacy: .public) zone=\(zone.name, privacy: .public) reason=no-window-available")
                    continue
                }
                let target = available.remove(at: idx)

                let beforeFrame = target.axFrame

                // Idempotence: window already at target → skip the AX write.
                // Tolerance matches `StandardWindowMover` (< 2 AX points per
                // axis); below that, re-issuing the write is a no-op that
                // can still flash focus / trigger animations on Spaces that
                // contain the target window.
                if let before = beforeFrame, Self.framesEqualWithinTolerance(before, targetAX) {
                    log.notice("restore-item id=\(restoreID, privacy: .public) bundle=\(bundleID, privacy: .public) zone=\(zone.name, privacy: .public) before=\(Self.fmt(before), privacy: .public) target=\(Self.fmt(targetAX), privacy: .public) skipped=already-at-target")
                    applied += 1
                    continue
                }

                let profile = appRuleStore.profile(forBundleID: bundleID, on: screen)
                let moveResult = mover.move(target, to: targetAX, profile: profile)
                let afterFrame = target.axFrame

                let beforeStr = beforeFrame.map { Self.fmt($0) } ?? "nil"
                let afterStr = afterFrame.map { Self.fmt($0) } ?? "nil"
                let targetStr = Self.fmt(targetAX)
                let preDelta = beforeFrame.map { Self.delta($0, vs: targetAX) } ?? "nil"
                let postDelta = afterFrame.map { Self.delta($0, vs: targetAX) } ?? "nil"

                log.notice("restore-item id=\(restoreID, privacy: .public) bundle=\(bundleID, privacy: .public) zone=\(zone.name, privacy: .public) before=\(beforeStr, privacy: .public) target=\(targetStr, privacy: .public) after=\(afterStr, privacy: .public) preΔ=\(preDelta, privacy: .public) postΔ=\(postDelta, privacy: .public) moverOK=\(moveResult, privacy: .public)")

                if moveResult {
                    applied += 1
                }
            }
        }
        log.notice("restore-end id=\(restoreID, privacy: .public) workspace='\(workspace.name, privacy: .public)' applied=\(applied, privacy: .public)/\(workspace.items.count, privacy: .public)")
        return applied
    }

    private static func framesEqualWithinTolerance(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.origin.x - b.origin.x) < tolerance &&
        abs(a.origin.y - b.origin.y) < tolerance &&
        abs(a.size.width - b.size.width) < tolerance &&
        abs(a.size.height - b.size.height) < tolerance
    }

    private static func fmt(_ rect: CGRect) -> String {
        String(format: "(%.0f,%.0f %.0fx%.0f)", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }

    private static func delta(_ rect: CGRect, vs target: CGRect) -> String {
        String(format: "(dx=%.0f dy=%.0f dw=%.0f dh=%.0f)",
               rect.origin.x - target.origin.x,
               rect.origin.y - target.origin.y,
               rect.width - target.width,
               rect.height - target.height)
    }
}

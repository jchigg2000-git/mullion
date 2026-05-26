import AppKit
import ApplicationServices
import os

/// Walks running apps on launch and re-applies the zone resolved by
/// `PlacementResolver` (AppRule → LearnedPlacement). Apps with no rule and
/// no history are left alone.
final class AutoRestore {
    private let log = Logger(subsystem: "com.mullion.Mullion", category: "auto-restore")
    private let layoutStore: LayoutStore
    private let appRuleStore: AppRuleStore
    private let historyStore: WindowHistoryStore
    private let mover: any WindowMover

    init(layoutStore: LayoutStore,
         appRuleStore: AppRuleStore,
         historyStore: WindowHistoryStore,
         mover: any WindowMover) {
        self.layoutStore = layoutStore
        self.appRuleStore = appRuleStore
        self.historyStore = historyStore
        self.mover = mover
    }

    func run() {
        let resolver = PlacementResolver(
            ruleStore: appRuleStore,
            historyStore: historyStore,
            layoutStore: layoutStore
        )

        for runningApp in NSWorkspace.shared.runningApplications {
            guard runningApp.activationPolicy == .regular,
                  let bundleID = runningApp.bundleIdentifier
            else { continue }

            let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
            var windowsRef: AnyObject?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement]
            else { continue }

            for window in windows {
                let ax = AXWindow(element: window, pid: runningApp.processIdentifier)
                guard let axFrame = ax.axFrame,
                      let appKitFrame = Geometry.axToAppKit(axFrame),
                      let screen = Geometry.screen(containingAppKitRect: appKitFrame),
                      let zone = resolver.resolveZone(bundleID: bundleID, on: screen)
                else { continue }

                let layout = layoutStore.layout(containingZoneID: zone.id)
                let targetAppKit = FrameResolver.appKitFrame(for: zone, in: layout, on: screen)
                guard let targetAX = Geometry.appKitToAX(targetAppKit) else { continue }
                let profile = appRuleStore.profile(forBundleID: bundleID, on: screen)
                if !mover.move(ax, to: targetAX, profile: profile) {
                    log.debug("auto-restore did not land near target for \(bundleID, privacy: .public) zone=\(zone.name, privacy: .public) profile=\(profile.rawValue, privacy: .public)")
                }
            }
        }
    }
}

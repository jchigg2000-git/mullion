import AppKit

/// Resolution order: explicit AppRule → LearnedPlacement → nothing.
@MainActor
final class PlacementResolver {
    private let ruleStore: AppRuleStore
    private let historyStore: WindowHistoryStore
    private let layoutStore: LayoutStore

    init(ruleStore: AppRuleStore, historyStore: WindowHistoryStore, layoutStore: LayoutStore) {
        self.ruleStore = ruleStore
        self.historyStore = historyStore
        self.layoutStore = layoutStore
    }

    func resolveZone(bundleID: String, on screen: NSScreen) -> Zone? {
        let uuid = DisplayRegistry.uuid(for: screen)
        let aspectRatio = Double(screen.frame.width / screen.frame.height)

        for rule in ruleStore.rules where rule.bundleID == bundleID {
            if rule.displayPredicate.matches(uuid: uuid, aspectRatio: aspectRatio),
               let zone = layoutStore.zone(withID: rule.preferredZoneID) {
                return zone
            }
        }

        if let placement = historyStore.placement(bundleID: bundleID, displayUUID: uuid),
           let zone = layoutStore.zone(withID: placement.zoneID) {
            return zone
        }
        return nil
    }
}

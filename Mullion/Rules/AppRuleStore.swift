import AppKit
import Foundation

@MainActor
final class AppRuleStore {
    private let store: JSONStore<AppRuleCatalog>

    init(url: URL = ApplicationSupport.url(for: "app-rules.json")) {
        self.store = JSONStore(url: url, default: AppRuleCatalog(rules: []))
    }

    var rules: [AppRule] { store.value.rules }

    func reload() { store.reload() }

    func upsert(_ rule: AppRule) {
        store.update { catalog in
            if let idx = catalog.rules.firstIndex(where: { $0.id == rule.id }) {
                catalog.rules[idx] = rule
            } else {
                catalog.rules.append(rule)
            }
        }
    }

    func remove(ruleWithID id: UUID) {
        store.update { catalog in
            catalog.rules.removeAll { $0.id == id }
        }
    }

    /// Returns the compatibility profile to use for `bundleID` when its
    /// window currently lives on `screen`. Walks rules in order, picking
    /// the first whose bundleID matches and whose displayPredicate matches
    /// `screen`. Defaults to `.standard` when no rule applies.
    func profile(forBundleID bundleID: String, on screen: NSScreen) -> CompatProfile {
        let uuid = DisplayRegistry.uuid(for: screen)
        let aspect = Double(screen.frame.width / screen.frame.height)
        for rule in rules where rule.bundleID == bundleID {
            if rule.displayPredicate.matches(uuid: uuid, aspectRatio: aspect) {
                return rule.compatibilityProfile
            }
        }
        return .standard
    }
}

import Foundation

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
}

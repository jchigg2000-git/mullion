import Foundation

final class ArrangementStore {
    private let store: JSONStore<ArrangementCatalog>

    init(url: URL = ApplicationSupport.url(for: "arrangements.json")) {
        self.store = JSONStore(url: url, default: ArrangementCatalog(arrangements: []))
    }

    var arrangements: [Arrangement] { store.value.arrangements }

    func reload() { store.reload() }

    func upsert(_ arrangement: Arrangement) {
        store.update { catalog in
            if let idx = catalog.arrangements.firstIndex(where: { $0.id == arrangement.id }) {
                catalog.arrangements[idx] = arrangement
            } else {
                catalog.arrangements.append(arrangement)
            }
        }
    }

    func remove(arrangementWithID id: UUID) {
        store.update { catalog in
            catalog.arrangements.removeAll { $0.id == id }
        }
    }

    /// Exact-match lookup against the canonical signature. Used by
    /// `ArrangementRegistry` on every display-change event.
    func arrangement(matching signature: [DisplaySig]) -> Arrangement? {
        let target = Arrangement.canonical(signature)
        return arrangements.first { $0.signature == target }
    }
}

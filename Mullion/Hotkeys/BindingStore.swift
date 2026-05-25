import Foundation

final class BindingStore {
    private let store: JSONStore<BindingCatalog>

    init(url: URL = ApplicationSupport.url(for: "bindings.json")) {
        self.store = JSONStore(url: url, default: BindingCatalog(bindings: []))
    }

    var bindings: [HotkeyBinding] { store.value.bindings }

    func reload() { store.reload() }

    func upsert(_ binding: HotkeyBinding) {
        store.update { catalog in
            if let idx = catalog.bindings.firstIndex(where: { $0.id == binding.id }) {
                catalog.bindings[idx] = binding
            } else {
                catalog.bindings.append(binding)
            }
        }
    }

    func remove(bindingWithID id: UUID) {
        store.update { catalog in
            catalog.bindings.removeAll { $0.id == id }
        }
    }
}

import Foundation

@MainActor
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

    /// Ensure a snap binding under `shortcutName` exists and targets exactly
    /// `[zoneID]`. Keyed on shortcutName (the stable identity for this slot),
    /// not on targets — targets can drift if the user deletes and recreates
    /// zones, and keying on them would silently produce a duplicate binding
    /// with the same shortcutName, which `HotkeyManager.register` then
    /// double-registers.
    func setSnapBinding(forZoneID zoneID: UUID, shortcutName: String) {
        store.update { catalog in
            if let idx = catalog.bindings.firstIndex(where: { $0.shortcutName == shortcutName && $0.role == .snap }) {
                let existingID = catalog.bindings[idx].id
                catalog.bindings[idx] = HotkeyBinding(
                    id: existingID,
                    shortcutName: shortcutName,
                    targets: [zoneID],
                    role: .snap
                )
            } else {
                catalog.bindings.append(
                    HotkeyBinding(shortcutName: shortcutName, targets: [zoneID], role: .snap)
                )
            }
        }
    }

    /// Remove the snap binding under `shortcutName`. Multi-target cycles
    /// referencing this zone under different names are preserved.
    func removeSnapBinding(forZoneID zoneID: UUID, shortcutName: String) {
        store.update { catalog in
            catalog.bindings.removeAll { $0.shortcutName == shortcutName && $0.role == .snap }
        }
    }
}

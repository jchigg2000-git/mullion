import Foundation

final class LayoutStore {
    private let store: JSONStore<LayoutCatalog>

    init(url: URL = ApplicationSupport.url(for: "layouts.json"),
         defaults: [Layout] = LayoutStore.bundledDefaults()) {
        self.store = JSONStore(url: url, default: LayoutCatalog(layouts: defaults))
    }

    var layouts: [Layout] { store.value.layouts }

    func reload() {
        store.reload()
    }

    func upsert(_ layout: Layout) {
        store.update { catalog in
            if let idx = catalog.layouts.firstIndex(where: { $0.id == layout.id }) {
                catalog.layouts[idx] = layout
            } else {
                catalog.layouts.append(layout)
            }
        }
    }

    func remove(layoutWithID id: UUID) {
        store.update { catalog in
            catalog.layouts.removeAll { $0.id == id }
        }
    }

    func zone(withID id: UUID) -> Zone? {
        for layout in store.value.layouts {
            if let zone = layout.zones.first(where: { $0.id == id }) {
                return zone
            }
        }
        return nil
    }

    /// Loads `DefaultLayouts.json` from the app bundle. Empty array when run
    /// outside a bundle (unit tests).
    static func bundledDefaults() -> [Layout] {
        guard let url = Bundle.main.url(forResource: "DefaultLayouts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(LayoutCatalog.self, from: data)
        else { return [] }
        return catalog.layouts
    }
}

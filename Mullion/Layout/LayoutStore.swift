import Foundation
import os

@MainActor
final class LayoutStore {
    private let store: JSONStore<LayoutCatalog>

    init(url: URL = ApplicationSupport.url(for: "layouts.json"),
         defaults: [Layout] = LayoutStore.bundledDefaults()) {
        self.store = JSONStore(url: url, default: LayoutCatalog(layouts: defaults))
    }

    var layouts: [Layout] { store.value.layouts }

    /// The layout the active display *arrangement* nominates, when it has one.
    /// `ArrangementRegistry` already surfaces this on every match; before this
    /// existed the value was logged and then dropped, so a user picking a
    /// default layout for an arrangement had no effect on snapping.
    var preferredLayoutID: UUID?

    /// The single place that answers "which layout governs this screen right
    /// now". Every caller — the grid overlay, drag-to-snap, and snap-by-index —
    /// must agree, or the overlay shows one set of zones while the hotkeys
    /// snap into another.
    ///
    /// Order: the arrangement's nominated layout, then the most specific
    /// predicate, then declaration order as a stable final tiebreak.
    func layout(forScreenUUID uuid: String, aspectRatio: Double) -> Layout? {
        let candidates = layouts.filter {
            $0.displayPredicate.matches(uuid: uuid, aspectRatio: aspectRatio)
        }
        if let preferredLayoutID,
           let preferred = candidates.first(where: { $0.id == preferredLayoutID }) {
            return preferred
        }
        return candidates.enumerated().min { a, b in
            let sa = a.element.displayPredicate.specificity
            let sb = b.element.displayPredicate.specificity
            if sa != sb { return sa > sb }
            return a.offset < b.offset
        }?.element
    }

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

    /// Replace the entire layout list. Used by the editor's drag-to-reorder.
    /// Order is load-bearing: snap-by-index resolves to the first layout
    /// whose displayPredicate matches the screen, so reordering controls
    /// which layout wins on overlapping predicates.
    func replaceLayouts(_ layouts: [Layout]) {
        store.update { catalog in
            catalog.layouts = layouts
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

    /// Returns the layout that contains the given zone ID. Used by
    /// `FrameResolver` to apply layout-level `outerMargin` / `innerGap`.
    func layout(containingZoneID id: UUID) -> Layout? {
        store.value.layouts.first { $0.zones.contains(where: { $0.id == id }) }
    }

    /// Loads `DefaultLayouts.json` from the app bundle. Empty array when run
    /// outside a bundle (unit tests). `nonisolated` so it can serve as the
    /// default argument for `init(url:defaults:)` (default-arg expressions
    /// evaluate outside the type's actor context).
    nonisolated static func bundledDefaults() -> [Layout] {
        guard let url = Bundle.main.url(forResource: "DefaultLayouts", withExtension: "json") else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(LayoutCatalog.self, from: data).layouts
        } catch {
            Logger(subsystem: "com.mullion.Mullion", category: "layout-store")
                .error("Failed to load bundled DefaultLayouts.json: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

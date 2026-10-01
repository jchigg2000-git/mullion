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

    /// Where the layout nominated by the active display *arrangement* comes
    /// from. `followPreferredLayout(of:)` points it at the live arrangement
    /// match, so the answer is read at resolution time. It used to be a value
    /// pushed in on each arrangement transition, which went stale three ways:
    /// never applied for the arrangement already matching at launch, ignored
    /// when the matched arrangement's own default layout was edited, and kept
    /// after the displays changed to an unsaved arrangement.
    var preferredLayoutProvider: @MainActor () -> UUID? = { nil }

    /// The layout the active display arrangement nominates, when it has one.
    var preferredLayoutID: UUID? { preferredLayoutProvider() }

    /// Track `registry`'s current match: its `defaultLayoutID` is preferred
    /// while an arrangement matches, nothing is preferred when none does.
    func followPreferredLayout(of registry: ArrangementRegistry) {
        preferredLayoutProvider = { [weak registry] in registry?.currentMatch?.defaultLayoutID }
    }

    /// The single place that answers "which layout governs this screen right
    /// now". Every caller — the grid overlay, drag-to-snap, and snap-by-index —
    /// must agree, or the overlay shows one set of zones while the hotkeys
    /// snap into another.
    ///
    /// Order: the arrangement's nominated layout, then the most specific
    /// predicate, then declaration order as a stable final tiebreak.
    func layout(forScreenUUID uuid: String, aspectRatio: Double) -> Layout? {
        rankedLayouts(forScreenUUID: uuid, aspectRatio: aspectRatio).first
    }

    /// Every layout whose predicate matches the screen, best first: the
    /// governing layout, then the rest by specificity and declaration order.
    /// For callers that must consider more than the governing layout (a
    /// workspace capture looks for the zone a window already sits in, which
    /// may belong to a layout that isn't the governing one) but still need to
    /// try the governing layout first.
    func rankedLayouts(forScreenUUID uuid: String, aspectRatio: Double) -> [Layout] {
        var ranked = layouts.enumerated()
            .filter { $0.element.displayPredicate.matches(uuid: uuid, aspectRatio: aspectRatio) }
            .sorted { a, b in
                let sa = a.element.displayPredicate.specificity
                let sb = b.element.displayPredicate.specificity
                if sa != sb { return sa > sb }
                return a.offset < b.offset
            }
            .map(\.element)
        if let preferredLayoutID,
           let index = ranked.firstIndex(where: { $0.id == preferredLayoutID }) {
            ranked.insert(ranked.remove(at: index), at: 0)
        }
        return ranked
    }

    func reload() {
        store.reload()
    }

    /// Write any edit still inside its debounce window. Called on quit.
    func flushPendingWrites() { store.flushIfPending() }

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
    /// Order is the last tiebreak in `layout(forScreenUUID:aspectRatio:)`:
    /// among layouts equally specific for a screen, the earlier one wins.
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

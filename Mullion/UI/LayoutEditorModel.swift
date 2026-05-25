import AppKit
import Observation

/// SwiftUI-facing state for the layout editor. Wraps the app's shared
/// `LayoutStore` so edits propagate to live hotkey dispatch without a
/// manual "Reload Layouts" step, but holds a `workingCopy` so in-flight
/// edits don't spam disk writes (the store debounces writes, but we also
/// want a clear Save/Revert gesture).
@Observable
final class LayoutEditorModel {
    private let layoutStore: LayoutStore
    private let bindingsProvider: () -> [HotkeyBinding]

    /// All layouts as currently persisted (refreshed on save / revert / external reload).
    private(set) var layouts: [Layout]

    /// ID of the layout being edited. `nil` when no layout is selected.
    var selection: Layout.ID?

    /// Mutable copy of the selected layout. Changes here drive the inspector
    /// and preview without touching the store until `save()`.
    var workingCopy: Layout?

    /// ID of the zone currently selected in the inspector.
    var selectedZoneID: Zone.ID?

    /// Connected screens (refreshed when DisplayRegistry fires `onChange`).
    private(set) var screens: [NSScreen]

    /// UUID of the screen the preview is rendered against. `nil` falls back
    /// to the first screen at render time.
    var previewScreenUUID: String?

    /// Whatever was assigned to `DisplayRegistry.shared.onChange` before we
    /// took it over — re-invoked so we don't silently steal events from
    /// another subscriber, and restored on deinit.
    private let previousOnChange: (() -> Void)?

    init(layoutStore: LayoutStore,
         bindingsProvider: @escaping () -> [HotkeyBinding] = { [] }) {
        self.layoutStore = layoutStore
        self.bindingsProvider = bindingsProvider
        self.layouts = layoutStore.layouts
        self.screens = DisplayRegistry.shared.screens
        self.selection = layoutStore.layouts.first?.id
        if let first = layoutStore.layouts.first {
            self.workingCopy = first
            self.selectedZoneID = first.zones.first?.id
        }
        self.previousOnChange = DisplayRegistry.shared.onChange
        let chained = self.previousOnChange
        DisplayRegistry.shared.onChange = { [weak self] in
            chained?()
            guard let self else { return }
            self.screens = DisplayRegistry.shared.screens
        }
    }

    deinit {
        DisplayRegistry.shared.onChange = previousOnChange
    }

    // MARK: Selection

    func select(layoutID: Layout.ID?) {
        selection = layoutID
        if let id = layoutID, let layout = layoutStore.layouts.first(where: { $0.id == id }) {
            workingCopy = layout
            selectedZoneID = layout.zones.first?.id
        } else {
            workingCopy = nil
            selectedZoneID = nil
        }
    }

    // MARK: Dirty state

    var isDirty: Bool {
        guard let workingCopy, let stored = layoutStore.layouts.first(where: { $0.id == workingCopy.id }) else {
            // A new layout (not yet in the store) counts as dirty.
            return workingCopy != nil
        }
        return stored != workingCopy
    }

    // MARK: Mutations

    func save() {
        guard let workingCopy else { return }
        layoutStore.upsert(workingCopy)
        layouts = layoutStore.layouts
    }

    func revert() {
        guard let id = selection,
              let stored = layoutStore.layouts.first(where: { $0.id == id }) else {
            workingCopy = nil
            selectedZoneID = nil
            return
        }
        workingCopy = stored
        if let zoneID = selectedZoneID,
           stored.zones.contains(where: { $0.id == zoneID }) {
            // Keep selection.
        } else {
            selectedZoneID = stored.zones.first?.id
        }
    }

    func newLayout() {
        let layout = Layout(
            name: "Untitled layout",
            zones: [Zone(name: "Full", x: 0, y: 0, width: 1, height: 1)]
        )
        layoutStore.upsert(layout)
        layouts = layoutStore.layouts
        selection = layout.id
        workingCopy = layout
        selectedZoneID = layout.zones.first?.id
    }

    func deleteSelectedLayout() {
        guard let id = selection else { return }
        layoutStore.remove(layoutWithID: id)
        layouts = layoutStore.layouts
        selection = layouts.first?.id
        workingCopy = layouts.first
        selectedZoneID = workingCopy?.zones.first?.id
    }

    // MARK: Zone mutations (operate on workingCopy)

    func addZone() {
        guard var copy = workingCopy else { return }
        let zone = Zone(name: "New zone", x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        copy.zones.append(zone)
        workingCopy = copy
        selectedZoneID = zone.id
    }

    func duplicateSelectedZone() {
        guard var copy = workingCopy,
              let id = selectedZoneID,
              let source = copy.zones.first(where: { $0.id == id }) else { return }
        var dup = source
        dup = Zone(
            name: "\(source.name) copy",
            x: source.x,
            y: source.y,
            width: source.width,
            height: source.height,
            anchor: source.anchor,
            sizeOverride: source.sizeOverride
        )
        copy.zones.append(dup)
        workingCopy = copy
        selectedZoneID = dup.id
    }

    /// Returns the bindings that target the given zone — used to warn before
    /// destructive edits. Empty when no bindings reference the zone.
    func bindingsReferencing(zoneID: Zone.ID) -> [HotkeyBinding] {
        bindingsProvider().filter { $0.targets.contains(zoneID) }
    }

    func deleteSelectedZone() {
        guard var copy = workingCopy, let id = selectedZoneID else { return }
        copy.zones.removeAll { $0.id == id }
        workingCopy = copy
        selectedZoneID = copy.zones.first?.id
    }

    /// Mutate a zone within the working copy by ID.
    func updateZone(id: Zone.ID, _ transform: (inout Zone) -> Void) {
        guard var copy = workingCopy,
              let idx = copy.zones.firstIndex(where: { $0.id == id }) else { return }
        transform(&copy.zones[idx])
        workingCopy = copy
    }

    // MARK: Fill empty space
    //
    // One-shot bake (not a live constraint). Why one-shot: zones don't have a
    // parent/sibling relationship in the data model, so "live fill" would
    // require introducing a constraint system. A one-shot action keeps the
    // model unchanged and matches how the rest of the inspector works —
    // the user clicks, a number is written, manual edits still apply.
    //
    // Sibling detection: every other zone in the same layout. Overlap on the
    // perpendicular axis is what makes a sibling relevant — e.g., for "Fill
    // width" we only care about zones that occupy some of the same Y band.
    //
    // Multiple gaps: prefer the gap containing the zone's current center
    // (the user has positioned the zone *somewhere*, and they probably want
    // to fill where it already is). Fall back to the largest gap.

    /// Gap on the X axis the selected zone could expand into, or `nil` if
    /// siblings cover the full [0, 1] band at this zone's Y range.
    func gapForFillWidth() -> (x: Double, width: Double)? {
        guard let id = selectedZoneID,
              let copy = workingCopy,
              let zone = copy.zones.first(where: { $0.id == id }) else { return nil }
        return Self.gap(for: zone, in: copy.zones, axis: .horizontal)
            .map { (x: $0.start, width: $0.length) }
    }

    /// Gap on the Y axis the selected zone could expand into, or `nil` if
    /// siblings cover the full [0, 1] band at this zone's X range.
    func gapForFillHeight() -> (y: Double, height: Double)? {
        guard let id = selectedZoneID,
              let copy = workingCopy,
              let zone = copy.zones.first(where: { $0.id == id }) else { return nil }
        return Self.gap(for: zone, in: copy.zones, axis: .vertical)
            .map { (y: $0.start, height: $0.length) }
    }

    func fillWidth() {
        guard let id = selectedZoneID, let gap = gapForFillWidth() else { return }
        updateZone(id: id) { z in
            z.x = gap.x
            z.width = gap.width
        }
    }

    func fillHeight() {
        guard let id = selectedZoneID, let gap = gapForFillHeight() else { return }
        updateZone(id: id) { z in
            z.y = gap.y
            z.height = gap.height
        }
    }

    private enum FillAxis {
        case horizontal
        case vertical
    }

    /// Find a gap on `axis` that `zone` could fill, considering only siblings
    /// that overlap on the perpendicular axis. Gaps smaller than 1% of the
    /// display are filtered out as noise.
    private static func gap(for zone: Zone,
                            in zones: [Zone],
                            axis: FillAxis) -> (start: Double, length: Double)? {
        let start: (Zone) -> Double = { axis == .horizontal ? $0.x : $0.y }
        let length: (Zone) -> Double = { axis == .horizontal ? $0.width : $0.height }
        let perpStart: (Zone) -> Double = { axis == .horizontal ? $0.y : $0.x }
        let perpLength: (Zone) -> Double = { axis == .horizontal ? $0.height : $0.width }

        let perp1 = perpStart(zone)
        let perp2 = perp1 + perpLength(zone)

        let overlapping = zones.filter { other in
            guard other.id != zone.id else { return false }
            let o1 = perpStart(other)
            let o2 = o1 + perpLength(other)
            return o1 < perp2 && o2 > perp1
        }

        let raw = overlapping
            .map { (start($0), start($0) + length($0)) }
            .sorted { $0.0 < $1.0 }

        var merged: [(Double, Double)] = []
        for interval in raw {
            if let last = merged.last, interval.0 <= last.1 {
                merged[merged.count - 1] = (last.0, max(last.1, interval.1))
            } else {
                merged.append(interval)
            }
        }

        var gaps: [(Double, Double)] = []
        var cursor: Double = 0
        for interval in merged {
            if interval.0 > cursor { gaps.append((cursor, interval.0)) }
            cursor = max(cursor, interval.1)
        }
        if cursor < 1 { gaps.append((cursor, 1)) }

        let minimumGap = 0.01
        let viable = gaps.filter { $0.1 - $0.0 >= minimumGap }
        if viable.isEmpty { return nil }

        let center = start(zone) + length(zone) / 2
        if let containing = viable.first(where: { $0.0 <= center && center <= $0.1 }) {
            return (start: containing.0, length: containing.1 - containing.0)
        }
        return viable.max { ($0.1 - $0.0) < ($1.1 - $1.0) }
            .map { (start: $0.0, length: $0.1 - $0.0) }
    }

    // MARK: Preview screen

    /// The NSScreen to render the preview against. Picks (in order):
    /// 1. the user's explicit `previewScreenUUID` if it still maps to a screen,
    /// 2. a screen matching the layout's `displayPredicate`,
    /// 3. the first connected screen.
    func resolvedPreviewScreen() -> NSScreen? {
        if let uuid = previewScreenUUID,
           let screen = DisplayRegistry.shared.screen(forUUID: uuid) {
            return screen
        }
        if let layout = workingCopy {
            for screen in screens {
                let uuid = DisplayRegistry.uuid(for: screen)
                let aspect = Double(screen.frame.width / screen.frame.height)
                if layout.displayPredicate.matches(uuid: uuid, aspectRatio: aspect) {
                    return screen
                }
            }
        }
        return screens.first
    }
}

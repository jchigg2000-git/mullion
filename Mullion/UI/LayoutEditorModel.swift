import AppKit
import Observation

/// What's currently selected in the editor sidebar. Drives the detail view.
enum EditorSelection: Hashable {
    case layout(UUID)
    case appRule(UUID)
    case binding(UUID)
}

/// SwiftUI-facing state for the layout editor. Wraps the app's shared
/// `LayoutStore` so edits propagate to live hotkey dispatch without a
/// manual "Reload Layouts" step, but holds a `workingCopy` so in-flight
/// edits don't spam disk writes (the store debounces writes, but we also
/// want a clear Save/Revert gesture).
///
/// App rules and bindings are edit-immediate — there's no working-copy
/// dance because they're small, focused records and the latency-to-rule-
/// activation matters more than a save/revert affordance.
@Observable
@MainActor
final class LayoutEditorModel {
    private let layoutStore: LayoutStore
    private let bindingStore: BindingStore
    private let appRuleStore: AppRuleStore
    private let onBindingsChanged: (() -> Void)?

    /// All layouts as currently persisted (refreshed on save / revert / external reload).
    private(set) var layouts: [Layout]

    /// All app rules as currently persisted. Edit-immediate — write through.
    private(set) var appRules: [AppRule]

    /// All bindings as currently persisted. The Bindings sidebar section
    /// filters this to multi-target / `.focus` bindings (single-zone snaps
    /// stay on the per-zone Recorder inside the Layouts inspector).
    private(set) var bindings: [HotkeyBinding]

    /// What's currently selected in the editor sidebar. Drives the detail view.
    var selection: EditorSelection?

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
         bindingStore: BindingStore,
         appRuleStore: AppRuleStore,
         onBindingsChanged: (() -> Void)? = nil) {
        self.layoutStore = layoutStore
        self.bindingStore = bindingStore
        self.appRuleStore = appRuleStore
        self.onBindingsChanged = onBindingsChanged
        self.layouts = layoutStore.layouts
        self.appRules = appRuleStore.rules
        self.bindings = bindingStore.bindings
        self.screens = DisplayRegistry.shared.screens
        if let first = layoutStore.layouts.first {
            self.selection = .layout(first.id)
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

    /// Convenience: ID of the layout currently selected (if any).
    var selectedLayoutID: Layout.ID? {
        if case .layout(let id) = selection { return id }
        return nil
    }

    /// Called from a `.onChange(of: selection)` hook whenever the sidebar
    /// selection changes. Drives the layout working-copy side effect that
    /// used to live inside the now-removed `select(_:)` method. Selection
    /// itself is written via the direct `$model.selection` binding, which
    /// the List needs for its internal state to stay coherent with the
    /// model — wrapping it in a `Binding(get:, set:)` causes List to lose
    /// selection-acceptance after a sidebar mutation under @Observable.
    func onSelectionChanged() {
        switch selection {
        case .layout(let id):
            if let layout = layoutStore.layouts.first(where: { $0.id == id }) {
                // Only refresh working copy if the user navigated to a
                // *different* layout; otherwise we'd blow away unsaved edits
                // whenever the inspector causes a re-render.
                if workingCopy?.id != layout.id {
                    workingCopy = layout
                    selectedZoneID = layout.zones.first?.id
                }
            } else {
                workingCopy = nil
                selectedZoneID = nil
            }
        case .appRule, .binding, .none:
            // Switching to a non-layout section preserves any unsaved edits
            // to whichever layout was most recently opened, so the user can
            // bounce back and forth without losing them.
            break
        }
    }

    // MARK: Dirty state (layouts only — rules/bindings are edit-immediate)

    var isDirty: Bool {
        guard let workingCopy, let stored = layoutStore.layouts.first(where: { $0.id == workingCopy.id }) else {
            // A new layout (not yet in the store) counts as dirty.
            return workingCopy != nil
        }
        return stored != workingCopy
    }

    // MARK: Mutations — layouts

    func save() {
        guard let workingCopy else { return }
        layoutStore.upsert(workingCopy)
        layouts = layoutStore.layouts
    }

    func revert() {
        guard let id = selectedLayoutID,
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
        selection = .layout(layout.id)
        workingCopy = layout
        selectedZoneID = layout.zones.first?.id
    }

    /// Drag-to-reorder. Order matters: snap-by-index resolves to the first
    /// layout whose displayPredicate matches the screen.
    func moveLayouts(from source: IndexSet, to destination: Int) {
        var copy = layouts
        copy.move(fromOffsets: source, toOffset: destination)
        layoutStore.replaceLayouts(copy)
        layouts = layoutStore.layouts
    }

    /// Shift the selected layout one slot toward `direction`. Used by the
    /// ↑↓ buttons in the sidebar. No-op when no selection or already at the
    /// boundary in that direction.
    func moveSelectedLayout(direction: ReorderDirection) {
        guard let id = selectedLayoutID,
              let idx = layouts.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + direction.delta
        guard layouts.indices.contains(target) else { return }
        var copy = layouts
        copy.swapAt(idx, target)
        layoutStore.replaceLayouts(copy)
        layouts = layoutStore.layouts
    }

    var canMoveSelectedLayout: (up: Bool, down: Bool) {
        guard let id = selectedLayoutID,
              let idx = layouts.firstIndex(where: { $0.id == id }) else {
            return (false, false)
        }
        return (up: idx > 0, down: idx < layouts.count - 1)
    }

    /// Shift the selected zone within the working copy. Reordering zones
    /// changes their ⌥⌃ key index (zone[0] = ⌥⌃1, etc.), so this is also
    /// how the user remaps which zone gets which number.
    func moveSelectedZone(direction: ReorderDirection) {
        guard var copy = workingCopy,
              let id = selectedZoneID,
              let idx = copy.zones.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + direction.delta
        guard copy.zones.indices.contains(target) else { return }
        copy.zones.swapAt(idx, target)
        workingCopy = copy
    }

    var canMoveSelectedZone: (up: Bool, down: Bool) {
        guard let copy = workingCopy,
              let id = selectedZoneID,
              let idx = copy.zones.firstIndex(where: { $0.id == id }) else {
            return (false, false)
        }
        return (up: idx > 0, down: idx < copy.zones.count - 1)
    }

    enum ReorderDirection {
        case up, down
        var delta: Int { self == .up ? -1 : 1 }
    }

    func deleteSelectedLayout() {
        guard let id = selectedLayoutID else { return }
        layoutStore.remove(layoutWithID: id)
        layouts = layoutStore.layouts
        if let first = layouts.first {
            selection = .layout(first.id)
            workingCopy = first
            selectedZoneID = first.zones.first?.id
        } else {
            selection = nil
            workingCopy = nil
            selectedZoneID = nil
        }
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
        bindings.filter { $0.targets.contains(zoneID) }
    }

    /// Stable per-zone shortcut name for the user-managed Recorder slot.
    /// Lives in its own namespace so seeded multi-target / cycle bindings
    /// (e.g. `mullion.leftHalf`) keep working alongside.
    func shortcutName(forZoneID zoneID: Zone.ID) -> String {
        "mullion.zone.\(zoneID.uuidString)"
    }

    /// Called from the Recorder's onChange. Upserts or removes the snap
    /// binding to match the current shortcut state, then asks the host to
    /// re-register hotkeys.
    func applyShortcut(forZoneID zoneID: Zone.ID, hasShortcut: Bool) {
        let name = shortcutName(forZoneID: zoneID)
        if hasShortcut {
            bindingStore.setSnapBinding(forZoneID: zoneID, shortcutName: name)
        } else {
            bindingStore.removeSnapBinding(forZoneID: zoneID, shortcutName: name)
        }
        bindings = bindingStore.bindings
        onBindingsChanged?()
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

    /// The zone's natural pixel dimensions on the currently-previewed
    /// display, ignoring any in-flight `sizeOverride`. Powers the "Detect"
    /// button in the pixel-pinned-size editor: clicking it captures the
    /// zone's render size against the selected display so the user
    /// doesn't have to compute it by hand.
    func detectedPixelSize(forZoneID id: Zone.ID) -> CGSize? {
        guard let copy = workingCopy,
              let zone = copy.zones.first(where: { $0.id == id }),
              let screen = resolvedPreviewScreen() else { return nil }
        var probe = zone
        probe.sizeOverride = nil
        let rect = FrameResolver.appKitFrame(for: probe, in: copy, on: screen)
        return rect.size
    }

    // MARK: Mutations — app rules (edit-immediate)

    /// Flat (layout, zone) pairs across every layout. Used by the rule
    /// inspector's zone picker so a rule can target any zone in any layout.
    var allZonesForPicker: [(layoutName: String, zone: Zone)] {
        layouts.flatMap { layout in
            layout.zones.map { (layoutName: layout.name, zone: $0) }
        }
    }

    func zoneName(forID id: UUID) -> String? {
        layoutStore.zone(withID: id)?.name
    }

    func layoutName(containingZoneID id: UUID) -> String? {
        layouts.first { $0.zones.contains(where: { $0.id == id }) }?.name
    }

    func addAppRule() {
        // Seed with first running app + first available zone — gives the
        // form something selectable rather than dropping the user into an
        // empty-everything state.
        let seedBundleID = NSWorkspace.shared.runningApplications
            .first { $0.activationPolicy == .regular }?.bundleIdentifier ?? ""
        let seedZoneID = layoutStore.layouts.first?.zones.first?.id ?? UUID()
        let rule = AppRule(
            bundleID: seedBundleID,
            displayPredicate: .anyDisplay,
            preferredZoneID: seedZoneID,
            compatibilityProfile: .standard
        )
        appRuleStore.upsert(rule)
        appRules = appRuleStore.rules
        selection = .appRule(rule.id)
    }

    func updateAppRule(id: UUID, _ transform: (inout AppRule) -> Void) {
        guard var rule = appRuleStore.rules.first(where: { $0.id == id }) else { return }
        transform(&rule)
        appRuleStore.upsert(rule)
        appRules = appRuleStore.rules
    }

    func deleteAppRule(id: UUID) {
        appRuleStore.remove(ruleWithID: id)
        appRules = appRuleStore.rules
        if case .appRule(let selectedID) = selection, selectedID == id {
            selection = appRules.first.map { .appRule($0.id) }
        }
    }

    // MARK: Mutations — bindings (edit-immediate)

    /// Subset shown in the Bindings sidebar section. The per-zone Recorder
    /// in the Layouts inspector already handles single-target snap bindings;
    /// duplicating that surface here would confuse rather than help.
    var nonTrivialBindings: [HotkeyBinding] {
        bindings.filter { $0.role == .focus || $0.targets.count > 1 }
    }

    func addBinding() {
        let firstZoneID = layoutStore.layouts.first?.zones.first?.id ?? UUID()
        // Empty shortcutName means the Recorder shows "Record Shortcut"
        // until the user picks one. ActionDispatcher tolerates this — no
        // KeyboardShortcuts.Name registers without a chord, so it's inert.
        let binding = HotkeyBinding(
            shortcutName: "mullion.binding.\(UUID().uuidString)",
            targets: [firstZoneID],
            role: .snap
        )
        bindingStore.upsert(binding)
        bindings = bindingStore.bindings
        selection = .binding(binding.id)
        onBindingsChanged?()
    }

    func updateBinding(id: UUID, _ transform: (inout HotkeyBinding) -> Void) {
        guard var binding = bindingStore.bindings.first(where: { $0.id == id }) else { return }
        transform(&binding)
        bindingStore.upsert(binding)
        bindings = bindingStore.bindings
        onBindingsChanged?()
    }

    func deleteBinding(id: UUID) {
        bindingStore.remove(bindingWithID: id)
        bindings = bindingStore.bindings
        if case .binding(let selectedID) = selection, selectedID == id {
            selection = nonTrivialBindings.first.map { .binding($0.id) }
        }
        onBindingsChanged?()
    }

    /// Re-register hotkeys without mutating any store. Used by the bindings
    /// editor's KeyboardShortcuts.Recorder onChange — the library writes
    /// the chord to UserDefaults itself, but `HotkeyManager` still needs
    /// to re-register handlers for the new shortcut to take effect.
    func notifyBindingsChanged() {
        onBindingsChanged?()
    }

    /// Picks up external edits (FSEvents reload, manual "Reload") so the
    /// editor reflects the new on-disk state.
    ///
    /// When the currently-selected item has been deleted externally we also
    /// clear the working copy — otherwise `save()` would silently undo the
    /// external delete by re-upserting the in-memory copy on the next Save.
    func refreshFromStores() {
        layouts = layoutStore.layouts
        appRules = appRuleStore.rules
        bindings = bindingStore.bindings
        switch selection {
        case .layout(let id):
            if !layouts.contains(where: { $0.id == id }) {
                selection = nil
                workingCopy = nil
                selectedZoneID = nil
            }
        case .appRule(let id):
            if !appRules.contains(where: { $0.id == id }) { selection = nil }
        case .binding(let id):
            if !bindings.contains(where: { $0.id == id }) { selection = nil }
        case .none:
            break
        }
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

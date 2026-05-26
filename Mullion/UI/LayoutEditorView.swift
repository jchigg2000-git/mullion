import SwiftUI
import AppKit
import KeyboardShortcuts

struct LayoutEditorView: View {
    @Bindable var model: LayoutEditorModel

    @State private var showingDeleteZoneWarning: Bool = false
    @State private var bindingsBlockingDelete: [HotkeyBinding] = []

    /// Selection the user requested while a dirty layout was loaded.
    /// When set, the dirty-switch confirmation dialog is presented; the
    /// underlying `model.selection` is reverted to keep the dirty layout
    /// open until the user picks Save / Discard / Stay.
    @State private var pendingSwitchTarget: EditorSelection?

    var body: some View {
        // HSplitView (not NavigationSplitView) because the editor's sidebar
        // is the primary tool, not a collapsible navigation list — the
        // NavigationSplitView toolbar item to toggle the sidebar was
        // pushing the window title into truncation, and its rounded
        // sidebar chrome made the layout / rule / binding sections look
        // like a floating card rather than a panel of the window.
        HSplitView {
            sidebar
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            detail
                .frame(minWidth: 720)
        }
        .frame(minWidth: 1040, minHeight: 640)
        .onChange(of: model.selection) { _, newValue in
            // Re-entrant call from a manual revert below — skip so we don't
            // re-prompt for the selection state we just restored.
            if pendingSwitchTarget != nil { return }

            // The data-loss surface: a dirty layout's working copy gets
            // blown away when `onSelectionChanged` loads a different
            // layout. Catch the transition whether it's a direct
            // layout→layout click or a layout→rule→layout detour.
            if case .layout(let newID) = newValue,
               let working = model.workingCopy,
               working.id != newID,
               model.isDirty {
                pendingSwitchTarget = newValue
                model.selection = .layout(working.id)
                return
            }
            model.onSelectionChanged()
        }
        .confirmationDialog(
            "Unsaved layout changes",
            isPresented: Binding(
                get: { pendingSwitchTarget != nil },
                set: { presenting in if !presenting { pendingSwitchTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Save and switch") {
                let target = pendingSwitchTarget
                pendingSwitchTarget = nil
                model.save()
                if let target { model.selection = target }
            }
            Button("Discard changes", role: .destructive) {
                let target = pendingSwitchTarget
                pendingSwitchTarget = nil
                model.revert()
                if let target { model.selection = target }
            }
            Button("Stay on this layout", role: .cancel) {
                pendingSwitchTarget = nil
            }
        } message: {
            Text("You have unsaved edits to this layout. Switching will lose them unless you save first.")
        }
        .confirmationDialog(
            "Zone is bound to hotkey(s)",
            isPresented: $showingDeleteZoneWarning,
            titleVisibility: .visible
        ) {
            Button("Delete anyway", role: .destructive) {
                model.deleteSelectedZone()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let names = bindingsBlockingDelete.map { $0.shortcutName }.joined(separator: ", ")
            Text("This zone is referenced by: \(names). Deleting it leaves those bindings pointing at a missing zone until you edit bindings.json.")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.selection) {

                Section("Layouts") {
                    ForEach(model.layouts) { layout in
                        HStack {
                            Text(layout.name)
                            Spacer()
                            Text("\(layout.zones.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(EditorSelection.layout(layout.id))
                    }
                    .onMove { source, destination in
                        model.moveLayouts(from: source, to: destination)
                    }
                }

                Section("App Rules") {
                    if model.appRules.isEmpty {
                        Text("No rules yet")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    ForEach(model.appRules) { rule in
                        HStack {
                            Text(rule.bundleID.isEmpty ? "(no bundle)" : rule.bundleID)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if let zoneName = model.zoneName(forID: rule.preferredZoneID) {
                                Text(zoneName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(EditorSelection.appRule(rule.id))
                    }
                }

                Section("Bindings") {
                    if model.nonTrivialBindings.isEmpty {
                        Text("No cycle or focus bindings")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    ForEach(model.nonTrivialBindings) { binding in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(KeyboardShortcuts.getShortcut(
                                for: KeyboardShortcuts.Name(binding.shortcutName)
                            )?.description ?? "(no shortcut)")
                            .font(.system(.body, design: .monospaced))
                            Text("\(binding.role.rawValue) · \(binding.targets.count) zone\(binding.targets.count == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(EditorSelection.binding(binding.id))
                    }
                }
            }
            // Force `.inset` so SwiftUI doesn't infer a sidebar style now
            // that the parent isn't a NavigationSplitView. Sidebar style
            // adds back the rounded vibrancy chrome we're trying to drop.
            .listStyle(.inset)

            Divider()
            sidebarToolbar
        }
    }

    private var sidebarToolbar: some View {
        HStack(spacing: 4) {
            Menu {
                Button("New layout") { model.newLayout() }
                Button("New app rule") { model.addAppRule() }
                Button("New binding") { model.addBinding() }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add layout, app rule, or binding")

            Button {
                deleteSelected()
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(model.selection == nil)
            .help("Delete selected item")

            Spacer()

            // ↑↓ only meaningful for layouts (order = snap-by-index match
            // order). For rules and bindings, reorder has no observable
            // semantics, so the buttons are inert there.
            Button {
                model.moveSelectedLayout(direction: .up)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(!model.canMoveSelectedLayout.up)
            .help("Move layout up — first match wins for ⌥⌃1..0")

            Button {
                model.moveSelectedLayout(direction: .down)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(!model.canMoveSelectedLayout.down)
            .help("Move layout down")
        }
        .padding(8)
    }

    private func deleteSelected() {
        switch model.selection {
        case .layout:
            model.deleteSelectedLayout()
        case .appRule(let id):
            model.deleteAppRule(id: id)
        case .binding(let id):
            model.deleteBinding(id: id)
        case .none:
            break
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .layout:
            if model.workingCopy != nil {
                layoutDetail
            } else {
                ContentUnavailableView(
                    "No layout selected",
                    systemImage: "rectangle.3.group",
                    description: Text("Pick a layout in the sidebar or create a new one.")
                )
            }
        case .appRule(let id):
            AppRulesEditorView(model: model, ruleID: id)
        case .binding(let id):
            BindingsEditorView(model: model, bindingID: id)
        case .none:
            ContentUnavailableView(
                "Nothing selected",
                systemImage: "sidebar.left",
                description: Text("Pick a layout, rule, or binding in the sidebar.")
            )
        }
    }

    private var layoutDetail: some View {
        HSplitView {
            inspector
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            preview
                .frame(minWidth: 360)
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                layoutFields
                Divider()
                zoneList
                Divider()
                zoneInspector
            }
            .padding(16)
        }
    }

    private var layoutFields: some View {
        Group {
            if let copy = model.workingCopy {
                VStack(alignment: .leading, spacing: 8) {
                    // No "Layout" header — the title-styled name field is
                    // self-evidently the layout name, and dropping the
                    // header buys vertical space the inspector badly needs.
                    // Rounded border (not .plain) so the field reads as
                    // editable — without it the title looked like a static
                    // label.
                    TextField("Layout name", text: Binding(
                        get: { copy.name },
                        set: { newValue in
                            var c = copy
                            c.name = newValue
                            model.workingCopy = c
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.title2.bold())

                    predicateEditor(copy: copy)
                    spacingEditor(copy: copy)
                }
            }
        }
    }

    private func spacingEditor(copy: Layout) -> some View {
        let gapBinding = Binding<Double>(
            get: { copy.innerGap },
            set: { newValue in
                var c = copy
                c.innerGap = max(0, newValue)
                model.workingCopy = c
            }
        )
        func marginBinding(_ keyPath: WritableKeyPath<LayoutInsets, Double>) -> Binding<Double> {
            Binding<Double>(
                get: { copy.outerMargin[keyPath: keyPath] },
                set: { newValue in
                    var c = copy
                    c.outerMargin[keyPath: keyPath] = max(0, newValue)
                    model.workingCopy = c
                }
            )
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Spacing")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("Inner gap")
                TextField("0", value: gapBinding, format: .number)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                Text("pt").foregroundStyle(.secondary)
                Spacer()
            }
            .help("Symmetric gap between adjacent zones. Edges that touch the layout boundary are not inset; outer spacing comes from the margin below.")

            HStack(spacing: 6) {
                Text("Margin")
                Text("T")
                TextField("0", value: marginBinding(\.top), format: .number)
                    .frame(width: 44)
                    .textFieldStyle(.roundedBorder)
                Text("L")
                TextField("0", value: marginBinding(\.leading), format: .number)
                    .frame(width: 44)
                    .textFieldStyle(.roundedBorder)
                Text("B")
                TextField("0", value: marginBinding(\.bottom), format: .number)
                    .frame(width: 44)
                    .textFieldStyle(.roundedBorder)
                Text("R")
                TextField("0", value: marginBinding(\.trailing), format: .number)
                    .frame(width: 44)
                    .textFieldStyle(.roundedBorder)
            }
            .help("Outer margin (pt) from the screen's visible frame. Top/Leading/Bottom/Trailing.")
        }
    }

    private func predicateEditor(copy: Layout) -> some View {
        let predicateKind: Binding<PredicateKind> = Binding(
            get: { PredicateKind.from(copy.displayPredicate) },
            set: { kind in
                var c = copy
                c.displayPredicate = kind.toPredicate(
                    aspect: kind.aspect(from: copy.displayPredicate),
                    uuid: kind.uuid(from: copy.displayPredicate, fallback: model.screens.first.map(DisplayRegistry.uuid(for:)))
                )
                model.workingCopy = c
            }
        )

        return VStack(alignment: .leading, spacing: 6) {
            Text("Targets")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("", selection: predicateKind) {
                Text("Any display").tag(PredicateKind.any)
                Text("Aspect ratio ≥").tag(PredicateKind.aspect)
                Text("Specific display").tag(PredicateKind.specific)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch copy.displayPredicate {
            case .anyDisplay:
                EmptyView()
            case .aspectRatioAtLeast(let minimum):
                HStack {
                    Text("≥")
                    TextField("min", value: Binding(
                        get: { minimum },
                        set: { newValue in
                            var c = copy
                            c.displayPredicate = .aspectRatioAtLeast(min: newValue)
                            model.workingCopy = c
                        }
                    ), format: .number.precision(.fractionLength(2)))
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    Text(":1").foregroundStyle(.secondary)
                }
            case .specificDisplay(let uuid):
                Picker("Display", selection: Binding(
                    get: { uuid },
                    set: { newValue in
                        var c = copy
                        c.displayPredicate = .specificDisplay(uuid: newValue)
                        model.workingCopy = c
                    }
                )) {
                    ForEach(model.screens, id: \.self) { screen in
                        let id = DisplayRegistry.uuid(for: screen)
                        Text(screen.localizedName).tag(id)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private var zoneList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Zones").font(.headline)
                Spacer()
                Button {
                    model.moveSelectedZone(direction: .up)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(!model.canMoveSelectedZone.up)
                .help("Move zone up — changes ⌥⌃ number assignment")

                Button {
                    model.moveSelectedZone(direction: .down)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(!model.canMoveSelectedZone.down)
                .help("Move zone down")

                Button {
                    model.addZone()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add zone")

                Button {
                    model.duplicateSelectedZone()
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .buttonStyle(.borderless)
                .disabled(model.selectedZoneID == nil)
                .help("Duplicate selected zone")

                Button {
                    requestDeleteZone()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(model.selectedZoneID == nil)
                .help("Delete selected zone")
            }

            if let copy = model.workingCopy {
                if copy.zones.isEmpty {
                    Text("No zones yet. Click + to add one.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(Array(copy.zones.enumerated()), id: \.element.id) { index, zone in
                        Button {
                            model.selectedZoneID = zone.id
                        } label: {
                            HStack(spacing: 6) {
                                if let key = ZoneIndexKey.label(for: index) {
                                    Text(key)
                                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(minWidth: 14)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(
                                            Capsule().fill(zone.id == model.selectedZoneID
                                                ? Color.accentColor
                                                : Color.accentColor.opacity(0.6))
                                        )
                                } else {
                                    Circle()
                                        .fill(zone.id == model.selectedZoneID ? Color.accentColor : Color.secondary.opacity(0.4))
                                        .frame(width: 8, height: 8)
                                }
                                Text(zone.name)
                                Spacer()
                                Text(zoneSummary(zone))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(zone.id == model.selectedZoneID
                                          ? Color.accentColor.opacity(0.15)
                                          : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func zoneSummary(_ zone: Zone) -> String {
        String(format: "%.2f,%.2f  %.2f×%.2f",
               zone.x, zone.y, zone.width, zone.height)
    }

    private var zoneInspector: some View {
        Group {
            if let copy = model.workingCopy,
               let id = model.selectedZoneID,
               let zone = copy.zones.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Zone").font(.headline)

                    TextField("Name", text: zoneBinding(\.name, fallback: zone.name))
                        .textFieldStyle(.roundedBorder)

                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                        GridRow {
                            Text("X")
                            stepper(value: zoneBinding(\.x, fallback: zone.x),
                                    presets: AxisPresets.xOrigin)
                        }
                        GridRow {
                            Text("Y")
                            stepper(value: zoneBinding(\.y, fallback: zone.y),
                                    presets: AxisPresets.yOrigin)
                        }
                        GridRow {
                            Text("Width")
                            stepper(value: zoneBinding(\.width, fallback: zone.width),
                                    presets: AxisPresets.widthSpan)
                        }
                        GridRow {
                            Text("Height")
                            stepper(value: zoneBinding(\.height, fallback: zone.height),
                                    presets: AxisPresets.heightSpan)
                        }
                    }

                    fillActions

                    Picker("Anchor", selection: zoneBinding(\.anchor, fallback: zone.anchor)) {
                        ForEach(Anchor.allCases, id: \.self) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }

                    hotkeyRecorder(for: id)

                    Toggle("Pixel-pinned size", isOn: Binding(
                        get: { zone.sizeOverride != nil },
                        set: { on in
                            model.updateZone(id: id) { z in
                                z.sizeOverride = on
                                    ? Zone.PixelSize(width: 1200, height: 800)
                                    : nil
                            }
                        }
                    ))

                    if let override = zone.sizeOverride {
                        let detected = model.detectedPixelSize(forZoneID: id)
                        HStack {
                            Text("W")
                            TextField("width", value: Binding(
                                get: { override.width },
                                set: { newValue in
                                    model.updateZone(id: id) { z in
                                        z.sizeOverride = Zone.PixelSize(width: newValue, height: override.height)
                                    }
                                }
                            ), format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            Text("H")
                            TextField("height", value: Binding(
                                get: { override.height },
                                set: { newValue in
                                    model.updateZone(id: id) { z in
                                        z.sizeOverride = Zone.PixelSize(width: override.width, height: newValue)
                                    }
                                }
                            ), format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            Text("px").foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                guard let size = detected else { return }
                                model.updateZone(id: id) { z in
                                    z.sizeOverride = Zone.PixelSize(
                                        width: round(size.width),
                                        height: round(size.height)
                                    )
                                }
                            } label: {
                                Label("Detect", systemImage: "viewfinder")
                            }
                            .controlSize(.small)
                            .disabled(detected == nil)
                            .help("Pull the zone's natural pixel size from the preview display.")
                        }
                    }
                }
            } else if model.workingCopy != nil {
                Text("Pick a zone above to edit it.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    private func hotkeyRecorder(for zoneID: Zone.ID) -> some View {
        let name = KeyboardShortcuts.Name(model.shortcutName(forZoneID: zoneID))
        let otherBindings = model
            .bindingsReferencing(zoneID: zoneID)
            .filter { $0.shortcutName != name.rawValue }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Hotkey")
                // .id(zoneID) forces SwiftUI to tear down and rebuild the
                // underlying NSViewRepresentable on zone selection change.
                // Recorder captures `onChange` once in makeNSView and never
                // refreshes it, so without this the closure would close over a
                // stale zoneID and write to the wrong zone's binding.
                KeyboardShortcuts.Recorder(for: name) { newShortcut in
                    model.applyShortcut(forZoneID: zoneID, hasShortcut: newShortcut != nil)
                }
                .id(zoneID)
            }
            if !otherBindings.isEmpty {
                // Seeded multi-target / cycle bindings target this zone too;
                // they're configured outside this Recorder. Surface them so
                // the user knows there's another path firing into this zone.
                Text("Also bound by: \(otherBindings.map { $0.shortcutName }.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stepper(value: Binding<Double>,
                         presets: [AxisPreset]) -> some View {
        HStack(spacing: 6) {
            TextField("", value: value, format: .number.precision(.fractionLength(3)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Stepper("", value: value, in: 0...1, step: 0.01)
                .labelsHidden()
            Menu {
                ForEach(presets) { preset in
                    Button(preset.label) { value.wrappedValue = preset.value }
                }
            } label: {
                Image(systemName: "percent")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Common percentages")
        }
    }

    @ViewBuilder
    private var fillActions: some View {
        let widthGap = model.gapForFillWidth()
        let heightGap = model.gapForFillHeight()
        HStack(spacing: 8) {
            Button {
                model.fillWidth()
            } label: {
                Label("Fill width", systemImage: "arrow.left.and.right")
            }
            .disabled(widthGap == nil)
            .help(widthGap.map { "Snap to gap \(String(format: "%.2f", $0.x))…\(String(format: "%.2f", $0.x + $0.width))" }
                  ?? "No horizontal gap among zones overlapping this Y band")

            Button {
                model.fillHeight()
            } label: {
                Label("Fill height", systemImage: "arrow.up.and.down")
            }
            .disabled(heightGap == nil)
            .help(heightGap.map { "Snap to gap \(String(format: "%.2f", $0.y))…\(String(format: "%.2f", $0.y + $0.height))" }
                  ?? "No vertical gap among zones overlapping this X band")
        }
    }

    /// Binding into a zone field on the working copy. Returns the fallback
    /// value when the selected zone is missing (shouldn't happen, but the
    /// Binding contract demands a value).
    private func zoneBinding<Value>(_ keyPath: WritableKeyPath<Zone, Value>,
                                    fallback: Value) -> Binding<Value> {
        Binding(
            get: {
                guard let id = model.selectedZoneID,
                      let copy = model.workingCopy,
                      let z = copy.zones.first(where: { $0.id == id }) else { return fallback }
                return z[keyPath: keyPath]
            },
            set: { newValue in
                guard let id = model.selectedZoneID else { return }
                model.updateZone(id: id) { z in
                    z[keyPath: keyPath] = newValue
                }
            }
        )
    }

    // MARK: Preview

    private var preview: some View {
        VStack(spacing: 8) {
            displayPicker
                .padding(.horizontal, 12)
                .padding(.top, 12)

            LivePreviewView(
                layout: model.workingCopy,
                displaySize: model.resolvedPreviewScreen()?.frame.size ?? CGSize(width: 3440, height: 1440),
                displayName: model.resolvedPreviewScreen()?.localizedName ?? "21:9 placeholder",
                selectedZoneID: model.selectedZoneID
            )
            .padding(12)

            actionBar
                .padding(12)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var displayPicker: some View {
        HStack {
            Text("Preview against:")
                .foregroundStyle(.secondary)
                .font(.caption)
            Picker("", selection: Binding(
                get: { model.previewScreenUUID ?? model.resolvedPreviewScreen().map(DisplayRegistry.uuid(for:)) ?? "" },
                set: { model.previewScreenUUID = $0.isEmpty ? nil : $0 }
            )) {
                ForEach(model.screens, id: \.self) { screen in
                    Text(screen.localizedName).tag(DisplayRegistry.uuid(for: screen))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)
            Spacer()
        }
    }

    private var actionBar: some View {
        HStack {
            if model.isDirty {
                Label("Unsaved changes", systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            Spacer()
            Button("Revert") { model.revert() }
                .disabled(!model.isDirty)
            Button("Save") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.isDirty)
        }
    }

    // MARK: Delete-zone gate

    private func requestDeleteZone() {
        guard let id = model.selectedZoneID else { return }
        let refs = model.bindingsReferencing(zoneID: id)
        if refs.isEmpty {
            model.deleteSelectedZone()
        } else {
            bindingsBlockingDelete = refs
            showingDeleteZoneWarning = true
        }
    }
}

// MARK: - Predicate-kind helper (shared with AppRulesEditorView)

enum PredicateKind: Hashable {
    case any
    case aspect
    case specific

    static func from(_ p: DisplayPredicate) -> PredicateKind {
        switch p {
        case .anyDisplay: return .any
        case .aspectRatioAtLeast: return .aspect
        case .specificDisplay: return .specific
        }
    }

    func toPredicate(aspect: Double, uuid: String?) -> DisplayPredicate {
        switch self {
        case .any:
            return .anyDisplay
        case .aspect:
            return .aspectRatioAtLeast(min: aspect)
        case .specific:
            return .specificDisplay(uuid: uuid ?? "")
        }
    }

    func aspect(from p: DisplayPredicate) -> Double {
        if case .aspectRatioAtLeast(let m) = p { return m }
        return 2.3
    }

    func uuid(from p: DisplayPredicate, fallback: String?) -> String? {
        if case .specificDisplay(let u) = p { return u }
        return fallback
    }
}

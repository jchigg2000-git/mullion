import SwiftUI
import AppKit

struct LayoutEditorView: View {
    @Bindable var model: LayoutEditorModel

    @State private var showingDeleteZoneWarning: Bool = false
    @State private var bindingsBlockingDelete: [HotkeyBinding] = []

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            if model.workingCopy != nil {
                detail
            } else {
                ContentUnavailableView(
                    "No layout selected",
                    systemImage: "rectangle.3.group",
                    description: Text("Pick a layout in the sidebar or create a new one.")
                )
            }
        }
        .frame(minWidth: 880, minHeight: 560)
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
            List(selection: Binding(
                get: { model.selection },
                set: { model.select(layoutID: $0) }
            )) {
                ForEach(model.layouts) { layout in
                    HStack {
                        Text(layout.name)
                        Spacer()
                        Text("\(layout.zones.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional(layout.id))
                }
            }

            Divider()

            HStack {
                Button {
                    model.newLayout()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New layout")

                Button {
                    model.deleteSelectedLayout()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(model.selection == nil)
                .help("Delete selected layout")

                Spacer()
            }
            .padding(8)
        }
    }

    // MARK: Detail

    private var detail: some View {
        HSplitView {
            inspector
                .frame(minWidth: 320, idealWidth: 360)
            preview
                .frame(minWidth: 360)
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                    Text("Layout").font(.headline)
                    TextField("Name", text: Binding(
                        get: { copy.name },
                        set: { newValue in
                            var c = copy
                            c.name = newValue
                            model.workingCopy = c
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    predicateEditor(copy: copy)
                }
            }
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
            case .aspectRatioAtLeast(let min):
                HStack {
                    Text("≥")
                    TextField("min", value: Binding(
                        get: { min },
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
            HStack {
                Text("Zones").font(.headline)
                Spacer()
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
                    ForEach(copy.zones) { zone in
                        Button {
                            model.selectedZoneID = zone.id
                        } label: {
                            HStack {
                                Circle()
                                    .fill(zone.id == model.selectedZoneID ? Color.accentColor : Color.secondary.opacity(0.4))
                                    .frame(width: 8, height: 8)
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
                            stepper(value: zoneBinding(\.x, fallback: zone.x))
                        }
                        GridRow {
                            Text("Y")
                            stepper(value: zoneBinding(\.y, fallback: zone.y))
                        }
                        GridRow {
                            Text("Width")
                            stepper(value: zoneBinding(\.width, fallback: zone.width))
                        }
                        GridRow {
                            Text("Height")
                            stepper(value: zoneBinding(\.height, fallback: zone.height))
                        }
                    }

                    Picker("Anchor", selection: zoneBinding(\.anchor, fallback: zone.anchor)) {
                        ForEach(Anchor.allCases, id: \.self) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }

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

    private func stepper(value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            TextField("", value: value, format: .number.precision(.fractionLength(3)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Stepper("", value: value, in: 0...1, step: 0.01)
                .labelsHidden()
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

// MARK: - Predicate-kind helper

private enum PredicateKind: Hashable {
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

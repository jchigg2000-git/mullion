import SwiftUI
import KeyboardShortcuts

/// Detail view for the Bindings sidebar section. Scope is narrow on purpose:
/// the per-zone Recorder inside the Layouts inspector already handles
/// single-target snap bindings — this view is for the bindings that one
/// can't, i.e. multi-target cycles and `.focus`-role bindings.
///
/// Edit-immediate: every field change writes through
/// `LayoutEditorModel.updateBinding` so the active `HotkeyManager` re-
/// registers the binding on the next tick.
struct BindingsEditorView: View {
    @Bindable var model: LayoutEditorModel
    let bindingID: UUID

    private var binding: HotkeyBinding? {
        model.bindings.first { $0.id == bindingID }
    }

    var body: some View {
        Group {
            if let binding {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Binding")
                                .font(.title2.bold())
                            Spacer()
                            Label("Saves automatically", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .labelStyle(.titleAndIcon)
                        }

                        shortcutSection(binding: binding)
                        roleSection(binding: binding)
                        targetsSection(binding: binding)
                        helpSection(binding: binding)
                    }
                    .padding(20)
                    .frame(maxWidth: 640, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    "Binding not found",
                    systemImage: "questionmark.app",
                    description: Text("Pick another binding in the sidebar.")
                )
            }
        }
    }

    // MARK: Sections

    private func shortcutSection(binding: HotkeyBinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hotkey")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            // .id forces the Recorder to rebuild when the binding ID
            // changes, the same pattern used for per-zone Recorder slots
            // in the Layouts inspector. The onChange closure re-registers
            // bindings immediately so the new chord is live without
            // waiting for an FSEvents-driven reload pass.
            KeyboardShortcuts.Recorder(
                for: KeyboardShortcuts.Name(binding.shortcutName)
            ) { _ in
                model.notifyBindingsChanged()
            }
            .id(bindingID)
            Text("Reserved chords (⌥⌃1..⌥⌃0) belong to snap-by-index — pick something else.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func roleSection(binding: HotkeyBinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Role")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { binding.role },
                set: { newValue in
                    model.updateBinding(id: bindingID) { $0.role = newValue }
                }
            )) {
                Text("Snap").tag(HotkeyBinding.Role.snap)
                Text("Focus").tag(HotkeyBinding.Role.focus)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(roleHelp(for: binding.role))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func roleHelp(for role: HotkeyBinding.Role) -> String {
        switch role {
        case .snap:
            return "Snap the focused window into the next zone in the cycle."
        case .focus:
            return "Raise the most-recent window that was snapped into the next zone in the cycle."
        }
    }

    private func targetsSection(binding: HotkeyBinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Targets")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                addZoneMenu(binding: binding)
            }

            if binding.targets.isEmpty {
                Text("Add at least one zone — empty bindings are inert.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                // Composite (index, zoneID) identity. Index alone makes
                // SwiftUI route taps to the wrong row during reorder/remove;
                // zoneID alone collapses if a cycle binding repeats a zone.
                ForEach(targetRows(for: binding), id: \.self) { row in
                    targetRow(binding: binding, index: row.index, zoneID: row.zoneID)
                }
            }

            if binding.targets.count > 1 {
                Text("Press the hotkey to cycle through targets in order. Each window remembers its own position in the cycle.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct TargetRow: Hashable {
        let index: Int
        let zoneID: UUID
    }

    private func targetRows(for binding: HotkeyBinding) -> [TargetRow] {
        binding.targets.enumerated().map { TargetRow(index: $0.offset, zoneID: $0.element) }
    }

    private func targetRow(binding: HotkeyBinding, index: Int, zoneID: UUID) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            if let zoneName = model.zoneName(forID: zoneID) {
                Text(zoneName)
                if let layoutName = model.layoutName(containingZoneID: zoneID) {
                    Text("· \(layoutName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("Missing zone", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button {
                model.updateBinding(id: bindingID) {
                    guard $0.targets.indices.contains(index), index > 0 else { return }
                    $0.targets.swapAt(index, index - 1)
                }
            } label: { Image(systemName: "chevron.up") }
            .buttonStyle(.borderless)
            .disabled(index == 0)

            Button {
                model.updateBinding(id: bindingID) {
                    guard $0.targets.indices.contains(index), index < $0.targets.count - 1 else { return }
                    $0.targets.swapAt(index, index + 1)
                }
            } label: { Image(systemName: "chevron.down") }
            .buttonStyle(.borderless)
            .disabled(index >= binding.targets.count - 1)

            Button {
                model.updateBinding(id: bindingID) {
                    guard $0.targets.indices.contains(index) else { return }
                    $0.targets.remove(at: index)
                }
            } label: { Image(systemName: "trash") }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func addZoneMenu(binding: HotkeyBinding) -> some View {
        Menu {
            ForEach(model.layouts) { layout in
                Section(layout.name) {
                    ForEach(layout.zones) { zone in
                        Button(zone.name) {
                            model.updateBinding(id: bindingID) { $0.targets.append(zone.id) }
                        }
                    }
                }
            }
        } label: {
            Label("Add target", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func helpSection(binding: HotkeyBinding) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shortcut name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(binding.shortcutName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

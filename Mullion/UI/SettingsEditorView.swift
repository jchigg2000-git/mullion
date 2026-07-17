import SwiftUI

/// Detail view for the Preferences sidebar entry. Edit-immediate: every
/// change writes through `LayoutEditorModel`, which mirrors it into
/// `SettingsStore` (debounced disk write). The overlay controllers read
/// `settingsStore.settings` live on each mouse / flags event, so a change
/// here takes effect on the very next gesture — no restart required.
///
/// Before this pane, `dragSnapModifier` and `gridModifier` could only be
/// changed by hand-editing `settings.json`; this closes the last primitive
/// without a UI surface (design-doc north star).
struct SettingsEditorView: View {
    @Bindable var model: LayoutEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Preferences")
                        .font(.title2.bold())
                    Spacer()
                    Label("Saves automatically", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }

                gesturesSection
                autoRestoreSection
                collisionNote
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Sections

    private var gesturesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gesture modifiers")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            modifierPicker(
                title: "Drag-to-snap",
                help: "Hold this modifier while dragging a window to reveal snap zones and drop the window into one.",
                selection: $model.dragSnapModifier
            )

            modifierPicker(
                title: "Grid overlay",
                help: "Hold this modifier to reveal the click-to-snap grid overlay over the focused window.",
                selection: $model.gridModifier
            )
        }
    }

    private func modifierPicker(title: String,
                                help: String,
                                selection: Binding<ModifierMask>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(title, selection: selection) {
                ForEach(ModifierMask.allCases, id: \.self) { mask in
                    Text(mask.displayName).tag(mask)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 380, alignment: .leading)

            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var autoRestoreSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Auto-restore")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle("Restore window placements automatically", isOn: $model.autoRestoreEnabled)

            Text("On launch and whenever the connected displays match a saved arrangement, re-apply the bound workspace. Also toggleable from the menu-bar item.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The two gestures are separated by exact-bitmask matching, so picking
    /// the same modifier (or a subset chord) for both is a foot-gun worth
    /// surfacing. Only flags an exact collision — `⌃` vs `⌃⌥` coexist fine.
    @ViewBuilder
    private var collisionNote: some View {
        if model.dragSnapModifier != .none,
           model.dragSnapModifier == model.gridModifier {
            Label(
                "Drag-to-snap and the grid overlay share the same modifier. Holding it will only trigger one of them.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }
}

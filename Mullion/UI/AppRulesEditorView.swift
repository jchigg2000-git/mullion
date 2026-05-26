import SwiftUI
import AppKit

/// Detail view for the App Rules sidebar section. Edit-immediate: every
/// field change writes through `LayoutEditorModel.updateAppRule` so the
/// active dispatcher and AutoRestore see the new rule on the next snap
/// without a Save step.
struct AppRulesEditorView: View {
    @Bindable var model: LayoutEditorModel
    let ruleID: UUID

    private var rule: AppRule? {
        model.appRules.first { $0.id == ruleID }
    }

    var body: some View {
        Group {
            if let rule {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("App Rule")
                                .font(.title2.bold())
                            Spacer()
                            Label("Saves automatically", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .labelStyle(.titleAndIcon)
                        }

                        bundleSection(rule: rule)
                        predicateSection(rule: rule)
                        zoneSection(rule: rule)
                        compatSection(rule: rule)
                        ruleDescription(rule: rule)
                    }
                    .padding(20)
                    .frame(maxWidth: 640, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    "Rule not found",
                    systemImage: "questionmark.app",
                    description: Text("Pick another rule in the sidebar.")
                )
            }
        }
    }

    // MARK: Sections

    private func bundleSection(rule: AppRule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bundle identifier")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("com.example.MyApp", text: Binding(
                    get: { rule.bundleID },
                    set: { newValue in
                        model.updateAppRule(id: ruleID) { $0.bundleID = newValue }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

                Menu {
                    let apps = NSWorkspace.shared.runningApplications
                        .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
                        .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
                    if apps.isEmpty {
                        Text("No regular apps running")
                    }
                    ForEach(apps, id: \.processIdentifier) { app in
                        Button {
                            if let bid = app.bundleIdentifier {
                                model.updateAppRule(id: ruleID) { $0.bundleID = bid }
                            }
                        } label: {
                            Text("\(app.localizedName ?? app.bundleIdentifier ?? "?")")
                        }
                    }
                } label: {
                    Label("Pick running app", systemImage: "list.bullet.rectangle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private func predicateSection(rule: AppRule) -> some View {
        let predicateKind: Binding<PredicateKind> = Binding(
            get: { PredicateKind.from(rule.displayPredicate) },
            set: { kind in
                let next = kind.toPredicate(
                    aspect: kind.aspect(from: rule.displayPredicate),
                    uuid: kind.uuid(from: rule.displayPredicate,
                                    fallback: model.screens.first.map(DisplayRegistry.uuid(for:)))
                )
                model.updateAppRule(id: ruleID) { $0.displayPredicate = next }
            }
        )

        return VStack(alignment: .leading, spacing: 6) {
            Text("Applies on")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("", selection: predicateKind) {
                Text("Any display").tag(PredicateKind.any)
                Text("Aspect ratio ≥").tag(PredicateKind.aspect)
                Text("Specific display").tag(PredicateKind.specific)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch rule.displayPredicate {
            case .anyDisplay:
                EmptyView()
            case .aspectRatioAtLeast(let minimum):
                HStack {
                    Text("≥")
                    TextField("min", value: Binding(
                        get: { minimum },
                        set: { newValue in
                            model.updateAppRule(id: ruleID) {
                                $0.displayPredicate = .aspectRatioAtLeast(min: newValue)
                            }
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
                        model.updateAppRule(id: ruleID) {
                            $0.displayPredicate = .specificDisplay(uuid: newValue)
                        }
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

    private func zoneSection(rule: AppRule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Snap to zone")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { rule.preferredZoneID },
                set: { newValue in
                    model.updateAppRule(id: ruleID) { $0.preferredZoneID = newValue }
                }
            )) {
                ForEach(model.layouts) { layout in
                    Section(layout.name) {
                        ForEach(layout.zones) { zone in
                            Text(zone.name).tag(zone.id)
                        }
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if model.zoneName(forID: rule.preferredZoneID) == nil {
                Label("This rule points at a zone that no longer exists.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func compatSection(rule: AppRule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Compatibility profile")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // .systemWindowManager is Phase G (not yet wired); the data
            // model keeps the case so JSON round-trips, but the picker
            // only offers what `WindowMutator` actually implements today.
            // When the rule was hand-edited to use it, surface the state
            // explicitly so picking another profile is an informed choice
            // rather than a silent overwrite.
            if rule.compatibilityProfile == .systemWindowManager {
                Label(
                    "This rule uses systemWindowManager (Phase G). Selecting Standard or Aggressive will replace it.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Picker("", selection: Binding(
                get: { rule.compatibilityProfile == .systemWindowManager ? .standard : rule.compatibilityProfile },
                set: { newValue in
                    model.updateAppRule(id: ruleID) { $0.compatibilityProfile = newValue }
                }
            )) {
                Text("Standard").tag(CompatProfile.standard)
                Text("Aggressive").tag(CompatProfile.aggressive)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(compatHelp(for: rule.compatibilityProfile))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func compatHelp(for profile: CompatProfile) -> String {
        switch profile {
        case .standard:
            return "Default. Size → position → size with AXEnhancedUserInterface toggled off."
        case .aggressive:
            return "Adds a settle delay and a post-write verify/retry. Use for Office/Electron apps that ignore the first write."
        case .systemWindowManager:
            return "Phase G escape hatch — not yet implemented; treated as Standard."
        }
    }

    private func ruleDescription(rule: AppRule) -> some View {
        let zoneName = model.zoneName(forID: rule.preferredZoneID) ?? "(missing zone)"
        let layoutName = model.layoutName(containingZoneID: rule.preferredZoneID) ?? "?"
        let where_: String
        switch rule.displayPredicate {
        case .anyDisplay: where_ = "any display"
        case .aspectRatioAtLeast(let minimum): where_ = String(format: "displays ≥ %.2f:1", minimum)
        case .specificDisplay: where_ = "a specific display"
        }
        return GroupBox {
            Text("On \(where_), snap **\(rule.bundleID.isEmpty ? "(no bundle)" : rule.bundleID)** into **\(zoneName)** of **\(layoutName)**.")
                .font(.callout)
                .padding(.vertical, 2)
        }
    }
}

import SwiftUI

/// Detail view for the Arrangements sidebar section. Edit-immediate: every
/// field change writes through `LayoutEditorModel.updateArrangement` so a
/// subsequent display-change event matches against the up-to-date catalog
/// without a Save step.
///
/// The signature itself is not hand-editable — the only signatures worth
/// saving are the ones the user's hardware actually produces, so capture +
/// recapture buttons replace it wholesale from `ArrangementRegistry`.
struct ArrangementsEditorView: View {
    @Bindable var model: LayoutEditorModel
    let arrangementID: UUID

    /// Sentinel UUID for the "None" entry in the default-layout Picker.
    /// SwiftUI Picker can't carry `nil` through a `Binding<UUID>` so a
    /// hand-rolled all-zeros UUID stands in. Hoisted to a static let so the
    /// initializer doesn't force-unwrap on every render.
    private static let noneLayoutSentinel = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )

    private var arrangement: Arrangement? {
        model.arrangements.first { $0.id == arrangementID }
    }

    var body: some View {
        Group {
            if let arrangement {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Arrangement")
                                .font(.title2.bold())
                            Spacer()
                            Label("Saves automatically", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .labelStyle(.titleAndIcon)
                        }

                        if model.matchedArrangementID == arrangement.id {
                            Label("Currently matching the connected displays.",
                                  systemImage: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }

                        nameSection(arrangement: arrangement)
                        defaultLayoutSection(arrangement: arrangement)
                        signatureSection(arrangement: arrangement)
                        arrangementDescription(arrangement: arrangement)
                    }
                    .padding(20)
                    .frame(maxWidth: 640, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    "Arrangement not found",
                    systemImage: "questionmark.app",
                    description: Text("Pick another arrangement in the sidebar.")
                )
            }
        }
    }

    // MARK: Sections

    private func nameSection(arrangement: Arrangement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Home desk", text: Binding(
                get: { arrangement.name },
                set: { newValue in
                    model.updateArrangement(id: arrangementID) { $0.name = newValue }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.title3)
        }
    }

    private func defaultLayoutSection(arrangement: Arrangement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Default layout")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { arrangement.defaultLayoutID ?? Self.noneLayoutSentinel },
                set: { newValue in
                    let next: UUID? = (newValue == Self.noneLayoutSentinel) ? nil : newValue
                    model.updateArrangement(id: arrangementID) { $0.defaultLayoutID = next }
                }
            )) {
                Text("None").tag(Self.noneLayoutSentinel)
                ForEach(model.layouts) { layout in
                    Text(layout.name).tag(layout.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Text("Applied when this arrangement matches the connected displays.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func signatureSection(arrangement: Arrangement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Displays")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.recaptureArrangementSignature(id: arrangementID)
                } label: {
                    Label("Recapture from current", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .help("Replace this arrangement's signature with the signature of the displays connected right now.")
            }

            if arrangement.signature.isEmpty {
                Text("No displays in signature.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Grid(alignment: .leadingFirstTextBaseline,
                     horizontalSpacing: 12,
                     verticalSpacing: 4) {
                    GridRow {
                        Text("Display UUID").font(.caption.bold())
                        Text("Size (pt)").font(.caption.bold())
                        Text("Origin (pt)").font(.caption.bold())
                    }
                    .foregroundStyle(.secondary)
                    ForEach(arrangement.signature, id: \.displayUUID) { sig in
                        GridRow {
                            Text(sig.displayUUID.prefix(8) + "…")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .help(sig.displayUUID)
                            Text("\(sig.widthPoints) × \(sig.heightPoints)")
                                .font(.system(.caption, design: .monospaced))
                            Text("(\(sig.originX), \(sig.originY))")
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
        }
    }

    private func arrangementDescription(arrangement: Arrangement) -> some View {
        let layoutName = arrangement.defaultLayoutID.flatMap { id in
            model.layouts.first { $0.id == id }?.name
        } ?? "no layout"
        let count = arrangement.signature.count
        let displays = count == 1 ? "1 display" : "\(count) displays"
        return GroupBox {
            Text("When **\(displays)** matches this signature, prefer **\(layoutName)**.")
                .font(.callout)
                .padding(.vertical, 2)
        }
    }
}

import SwiftUI

/// Detail view for the Workspaces sidebar section. Edit-immediate for the
/// name field; items are captured/recaptured wholesale rather than edited
/// in-place (consistent with how arrangements treat their signature).
struct WorkspacesEditorView: View {
    @Bindable var model: LayoutEditorModel
    let workspaceID: UUID

    @State private var lastRestoreResult: RestoreResult?

    private struct RestoreResult: Identifiable {
        let id = UUID()
        let applied: Int
        let total: Int
    }

    private var workspace: Workspace? {
        model.workspaces.first { $0.id == workspaceID }
    }

    var body: some View {
        Group {
            if let workspace {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Workspace")
                                .font(.title2.bold())
                            Spacer()
                            Label("Saves automatically", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .labelStyle(.titleAndIcon)
                        }

                        nameSection(workspace: workspace)
                        actionSection(workspace: workspace)
                        itemsSection(workspace: workspace)
                        descriptionSection(workspace: workspace)
                    }
                    .padding(20)
                    .frame(maxWidth: 720, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    "Workspace not found",
                    systemImage: "questionmark.app",
                    description: Text("Pick another workspace in the sidebar.")
                )
            }
        }
    }

    // MARK: Sections

    private func nameSection(workspace: Workspace) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Morning setup", text: Binding(
                get: { workspace.name },
                set: { newValue in
                    model.updateWorkspace(id: workspaceID) { $0.name = newValue }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.title3)
        }
    }

    private func actionSection(workspace: Workspace) -> some View {
        HStack(spacing: 8) {
            Button {
                let applied = model.restoreWorkspace(id: workspaceID)
                lastRestoreResult = RestoreResult(applied: applied, total: workspace.items.count)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward.circle.fill")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .help("Apply this workspace to the running windows now.")

            Button {
                model.recaptureWorkspace(id: workspaceID)
                lastRestoreResult = nil
            } label: {
                Label("Recapture from current", systemImage: "arrow.clockwise")
            }
            .help("Replace this workspace's items with the windows on screen right now.")

            Spacer()

            if let result = lastRestoreResult {
                Label("Applied \(result.applied) of \(result.total)",
                      systemImage: result.applied == result.total ? "checkmark.seal.fill" : "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(result.applied == result.total ? .green : .secondary)
            }
        }
    }

    private func itemsSection(workspace: Workspace) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Captured windows")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(captureTimestamp(workspace.capturedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if workspace.items.isEmpty {
                Text("No windows captured — make sure apps are running with windows on visible displays, then recapture.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Grid(alignment: .leadingFirstTextBaseline,
                     horizontalSpacing: 12,
                     verticalSpacing: 4) {
                    GridRow {
                        Text("App").font(.caption.bold())
                        Text("Window").font(.caption.bold())
                        Text("Display").font(.caption.bold())
                        Text("Zone").font(.caption.bold())
                    }
                    .foregroundStyle(.secondary)
                    ForEach(workspace.items) { item in
                        GridRow {
                            Text(item.bundleID)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(item.bundleID)
                            Text(item.windowTitle ?? "—")
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(item.windowTitle == nil ? .secondary : .primary)
                            Text(item.displayUUID.prefix(8) + "…")
                                .font(.system(.caption, design: .monospaced))
                                .help(item.displayUUID)
                            Text(model.zoneName(forID: item.zoneID) ?? "(missing)")
                                .font(.caption)
                                .foregroundStyle(model.zoneName(forID: item.zoneID) == nil ? .orange : .primary)
                        }
                    }
                }
            }
        }
    }

    private func descriptionSection(workspace: Workspace) -> some View {
        let count = workspace.items.count
        let noun = count == 1 ? "window" : "windows"
        return GroupBox {
            Text("Restore will place **\(count) \(noun)** into their captured zones. Apps that aren't running or whose displays aren't connected are skipped.")
                .font(.callout)
                .padding(.vertical, 2)
        }
    }

    private func captureTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Captured \(formatter.string(from: date))"
    }
}

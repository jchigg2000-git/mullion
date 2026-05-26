import Foundation

@MainActor
final class WorkspaceStore {
    private let store: JSONStore<WorkspaceCatalog>

    init(url: URL = ApplicationSupport.url(for: "workspaces.json")) {
        self.store = JSONStore(url: url, default: WorkspaceCatalog())
    }

    var workspaces: [Workspace] { store.value.workspaces }

    func reload() { store.reload() }

    func upsert(_ workspace: Workspace) {
        store.update { catalog in
            if let idx = catalog.workspaces.firstIndex(where: { $0.id == workspace.id }) {
                catalog.workspaces[idx] = workspace
            } else {
                catalog.workspaces.append(workspace)
            }
        }
    }

    func remove(workspaceWithID id: UUID) {
        store.update { catalog in
            catalog.workspaces.removeAll { $0.id == id }
        }
    }
}

import XCTest
@testable import Mullion

/// Regression cover for workspace re-capture. `recaptureWorkspace` used to run
/// `captureCurrent` (which saves a brand-new workspace) and then delete that
/// throwaway, so the store briefly held a workspace the user never asked for.
/// It now takes a `snapshot` that never touches the store.
@MainActor
final class WorkspaceControllerTests: XCTestCase {

    private func makeController() -> (WorkspaceController, WorkspaceStore) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let id = UUID().uuidString
        let workspaceURL = dir.appendingPathComponent("workspaces-\(id).json")
        let rulesURL = dir.appendingPathComponent("app-rules-\(id).json")
        let layoutsURL = dir.appendingPathComponent("layouts-\(id).json")
        addTeardownBlock {
            for url in [workspaceURL, rulesURL, layoutsURL] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        // No layouts, so no window can land in a zone and the capture is
        // empty and deterministic whatever is running on this machine.
        let workspaceStore = WorkspaceStore(url: workspaceURL)
        let controller = WorkspaceController(
            layoutStore: LayoutStore(url: layoutsURL, defaults: []),
            workspaceStore: workspaceStore,
            appRuleStore: AppRuleStore(url: rulesURL)
        )
        return (controller, workspaceStore)
    }

    func test_snapshot_doesNotTouchTheStore() {
        let (controller, store) = makeController()

        let snapshot = controller.snapshot(name: "Scratch")

        XCTAssertEqual(snapshot.name, "Scratch")
        XCTAssertTrue(store.workspaces.isEmpty)
    }

    func test_captureCurrent_savesExactlyTheSnapshotItReturns() {
        let (controller, store) = makeController()

        let captured = controller.captureCurrent(name: "Desk")

        XCTAssertEqual(store.workspaces.map(\.id), [captured.id])
        XCTAssertEqual(store.workspaces.first?.name, "Desk")
    }
}

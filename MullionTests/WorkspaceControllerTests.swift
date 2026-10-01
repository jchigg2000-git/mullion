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

    // MARK: Which zone a captured window belongs to

    private func column(_ name: String, index: Int, of count: Int) -> Zone {
        Zone(name: name,
             x: Double(index) / Double(count), y: 0,
             width: 1.0 / Double(count), height: 1,
             anchor: .topLeft)
    }

    private let screen = CGRect(x: 0, y: 0, width: 3000, height: 1000)

    /// Regression: capture used the first matching layout in file order, so a
    /// window snapped into the left third of the layout the user snaps with
    /// was filed under the left half of an earlier-declared layout, and
    /// restore moved it there.
    func test_zoneID_prefersTheGoverningLayoutOverFileOrder() {
        let halfLeft = column("Half left", index: 0, of: 2)
        let halves = Layout(name: "Halves", zones: [halfLeft, column("Half right", index: 1, of: 2)])
        let thirdLeft = column("Third left", index: 0, of: 3)
        let thirds = Layout(name: "Thirds", zones: [thirdLeft, column("Third mid", index: 1, of: 3),
                                                    column("Third right", index: 2, of: 3)])

        // Window centre at x=500: inside the left half and the left third.
        let centre = CGPoint(x: 500, y: 500)
        // Ranked order puts the governing layout first, whatever the file order.
        XCTAssertEqual(WorkspaceController.zoneID(containing: centre, in: [thirds, halves], visibleFrame: screen),
                       thirdLeft.id)
        XCTAssertEqual(WorkspaceController.zoneID(containing: centre, in: [halves, thirds], visibleFrame: screen),
                       halfLeft.id)
    }

    func test_zoneID_fallsBackToOtherMatchingLayouts_andToNil() {
        let leftThird = column("Left third", index: 0, of: 3)
        let governing = Layout(name: "Left only", zones: [leftThird])
        let rightHalf = column("Right half", index: 1, of: 2)
        let other = Layout(name: "Other", zones: [rightHalf])

        // The point lies outside the governing layout's only zone, inside the
        // other layout's: a window snapped from the menu into a zone of a
        // non-governing layout is still captured.
        XCTAssertEqual(WorkspaceController.zoneID(containing: CGPoint(x: 2500, y: 500),
                                                  in: [governing, other], visibleFrame: screen),
                       rightHalf.id)
        XCTAssertNil(WorkspaceController.zoneID(containing: CGPoint(x: 1400, y: 500),
                                                in: [governing, other], visibleFrame: screen))
        XCTAssertNil(WorkspaceController.zoneID(containing: CGPoint(x: 100, y: 100),
                                                in: [], visibleFrame: screen))
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

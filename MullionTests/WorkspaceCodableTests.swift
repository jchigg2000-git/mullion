import XCTest
@testable import Mullion

final class WorkspaceCodableTests: XCTestCase {

    func test_workspaceItem_roundTrip() throws {
        let item = WorkspaceItem(
            bundleID: "com.apple.Safari",
            windowTitle: "Apple — Start",
            capturedAXFrame: CGRect(x: 100, y: 200, width: 800, height: 600),
            displayUUID: "37D8832A-2D66-02CA-B9F7-8F30A301B230",
            zoneID: UUID()
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(WorkspaceItem.self, from: data)
        XCTAssertEqual(item, decoded)
        XCTAssertEqual(decoded.capturedAXFrame, CGRect(x: 100, y: 200, width: 800, height: 600))
    }

    func test_workspaceItem_decodes_withoutCapturedFrame_legacyJSON() throws {
        // Workspaces.json written before capturedAXFrame shipped must still
        // load — decodeIfPresent lets the field default to nil.
        let legacyJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "bundleID": "com.apple.Safari",
          "windowTitle": "Apple",
          "displayUUID": "D1",
          "zoneID": "22222222-2222-2222-2222-222222222222"
        }
        """
        let item = try JSONDecoder().decode(WorkspaceItem.self,
                                            from: Data(legacyJSON.utf8))
        XCTAssertNil(item.capturedAXFrame)
        XCTAssertEqual(item.bundleID, "com.apple.Safari")
    }

    func test_workspaceItem_withoutTitle_roundTrip() throws {
        let item = WorkspaceItem(
            bundleID: "com.apple.Terminal",
            windowTitle: nil,
            displayUUID: "1AB2",
            zoneID: UUID()
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(WorkspaceItem.self, from: data)
        XCTAssertEqual(item, decoded)
        XCTAssertNil(decoded.windowTitle)
    }

    func test_workspace_roundTrip_preservesItemOrder() throws {
        let items = (0..<5).map { i in
            WorkspaceItem(
                bundleID: "com.example.app\(i)",
                windowTitle: "Window \(i)",
                displayUUID: "D\(i)",
                zoneID: UUID()
            )
        }
        let workspace = Workspace(
            name: "Morning setup",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            items: items
        )
        let data = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)
        XCTAssertEqual(workspace.id, decoded.id)
        XCTAssertEqual(workspace.name, decoded.name)
        XCTAssertEqual(workspace.capturedAt.timeIntervalSince1970,
                       decoded.capturedAt.timeIntervalSince1970,
                       accuracy: 0.001)
        XCTAssertEqual(workspace.items.map(\.id), decoded.items.map(\.id))
    }

    func test_workspaceCatalog_emptyDefault_encodes() throws {
        let catalog = WorkspaceCatalog()
        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(WorkspaceCatalog.self, from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertTrue(decoded.workspaces.isEmpty)
    }

    func test_workspace_roundTrip_withArrangementBinding() throws {
        let arrangementID = UUID()
        let workspace = Workspace(
            name: "Home desk",
            items: [
                WorkspaceItem(bundleID: "com.app.a",
                              displayUUID: "D1",
                              zoneID: UUID())
            ],
            arrangementID: arrangementID
        )
        let data = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)
        XCTAssertEqual(decoded.arrangementID, arrangementID)
    }

    func test_workspace_decodes_withoutArrangementID_legacyJSON() throws {
        // workspaces.json files written before #28 shipped must still load.
        let legacyJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Old workspace",
          "capturedAt": 700000000,
          "items": []
        }
        """
        let workspace = try JSONDecoder().decode(Workspace.self,
                                                 from: Data(legacyJSON.utf8))
        XCTAssertNil(workspace.arrangementID)
        XCTAssertEqual(workspace.name, "Old workspace")
    }

    func test_workspaceCatalog_multipleWorkspaces_roundTrip() throws {
        let catalog = WorkspaceCatalog(workspaces: [
            Workspace(name: "Home", items: [
                WorkspaceItem(bundleID: "com.app.a",
                              displayUUID: "D1",
                              zoneID: UUID())
            ]),
            Workspace(name: "Office", items: [
                WorkspaceItem(bundleID: "com.app.b",
                              displayUUID: "D2",
                              zoneID: UUID()),
                WorkspaceItem(bundleID: "com.app.c",
                              displayUUID: "D2",
                              zoneID: UUID())
            ])
        ])
        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(WorkspaceCatalog.self, from: data)
        XCTAssertEqual(decoded.workspaces.count, 2)
        XCTAssertEqual(decoded.workspaces[0].name, "Home")
        XCTAssertEqual(decoded.workspaces[0].items.count, 1)
        XCTAssertEqual(decoded.workspaces[1].name, "Office")
        XCTAssertEqual(decoded.workspaces[1].items.count, 2)
    }
}

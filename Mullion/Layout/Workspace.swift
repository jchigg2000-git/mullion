import Foundation

/// One captured window placement inside a workspace. Restored by finding a
/// running window with matching `bundleID` and assigning it to the zone via
/// the same mover chain `AutoRestore` uses.
///
/// `windowTitle` and `capturedAXFrame` are tiebreakers used to pick *which*
/// of an app's windows fills *which* item when an app has multiple windows
/// captured. `capturedAXFrame` wins over `windowTitle` because apps like
/// iTerm title every window the same string by default — the only reliable
/// per-window identifier we get without resorting to private AXWindowID APIs
/// is "where the window was sitting at capture time."
struct WorkspaceItem: Codable, Identifiable, Hashable {
    let id: UUID
    var bundleID: String
    var windowTitle: String?
    var capturedAXFrame: CGRect?
    var displayUUID: String
    var zoneID: UUID

    init(id: UUID = UUID(),
         bundleID: String,
         windowTitle: String? = nil,
         capturedAXFrame: CGRect? = nil,
         displayUUID: String,
         zoneID: UUID) {
        self.id = id
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.capturedAXFrame = capturedAXFrame
        self.displayUUID = displayUUID
        self.zoneID = zoneID
    }

    // Tolerate workspaces written before `capturedAXFrame` shipped.
    private enum CodingKeys: String, CodingKey {
        case id, bundleID, windowTitle, capturedAXFrame, displayUUID, zoneID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.bundleID = try c.decode(String.self, forKey: .bundleID)
        self.windowTitle = try c.decodeIfPresent(String.self, forKey: .windowTitle)
        self.capturedAXFrame = try c.decodeIfPresent(CGRect.self, forKey: .capturedAXFrame)
        self.displayUUID = try c.decode(String.self, forKey: .displayUUID)
        self.zoneID = try c.decode(UUID.self, forKey: .zoneID)
    }
}

/// A named snapshot of `[WorkspaceItem]` captured at `capturedAt`. Phase F #28
/// will add optional arrangement binding (`arrangementID`) — left out of the
/// type for #27 so the data file stays migration-friendly when #28 lands.
struct Workspace: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var capturedAt: Date
    var items: [WorkspaceItem]

    init(id: UUID = UUID(),
         name: String,
         capturedAt: Date = Date(),
         items: [WorkspaceItem] = []) {
        self.id = id
        self.name = name
        self.capturedAt = capturedAt
        self.items = items
    }
}

/// Persisted root for `workspaces.json`. Versioned the same way
/// `LayoutCatalog` / `AppRuleCatalog` / `ArrangementCatalog` are.
struct WorkspaceCatalog: Codable {
    var version: Int
    var workspaces: [Workspace]

    init(version: Int = 1, workspaces: [Workspace] = []) {
        self.version = version
        self.workspaces = workspaces
    }
}

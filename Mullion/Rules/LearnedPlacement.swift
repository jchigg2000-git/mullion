import Foundation

/// Auto-memory: the last zone an app's window was placed in on a given
/// display. Updated on every successful snap. Used by `PlacementResolver`
/// when no `AppRule` matches.
struct LearnedPlacement: Codable, Hashable {
    let bundleID: String
    let displayUUID: String
    var zoneID: UUID
    var placedAt: Date
}

struct LearnedPlacementCatalog: Codable {
    var version: Int
    var placements: [LearnedPlacement]

    init(version: Int = 1, placements: [LearnedPlacement]) {
        self.version = version
        self.placements = placements
    }
}

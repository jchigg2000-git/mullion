import Foundation

/// Explicit per-app placement preference. Overrides `LearnedPlacement`.
struct AppRule: Codable, Identifiable, Hashable {
    let id: UUID
    var bundleID: String
    var displayPredicate: DisplayPredicate
    var preferredZoneID: UUID

    init(id: UUID = UUID(),
         bundleID: String,
         displayPredicate: DisplayPredicate = .anyDisplay,
         preferredZoneID: UUID) {
        self.id = id
        self.bundleID = bundleID
        self.displayPredicate = displayPredicate
        self.preferredZoneID = preferredZoneID
    }
}

struct AppRuleCatalog: Codable {
    var version: Int
    var rules: [AppRule]

    init(version: Int = 1, rules: [AppRule]) {
        self.version = version
        self.rules = rules
    }
}

import Foundation

/// A named set of zones, optionally constrained to specific displays via
/// `displayPredicate`. In v1 the predicate is informational/grouping — zones
/// can be bound to hotkeys regardless of which display they were "designed for".
struct Layout: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var zones: [Zone]
    var displayPredicate: DisplayPredicate

    init(id: UUID = UUID(),
         name: String,
         zones: [Zone],
         displayPredicate: DisplayPredicate = .anyDisplay) {
        self.id = id
        self.name = name
        self.zones = zones
        self.displayPredicate = displayPredicate
    }
}

struct LayoutCatalog: Codable {
    var version: Int
    var layouts: [Layout]

    init(version: Int = 1, layouts: [Layout]) {
        self.version = version
        self.layouts = layouts
    }
}

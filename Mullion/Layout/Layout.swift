import Foundation

/// Symmetric per-edge insets in display points. Defined here (not as
/// `NSEdgeInsets`) so the Layout module stays AppKit-free and Codable
/// round-trips cleanly.
struct LayoutInsets: Codable, Hashable {
    var top: Double
    var leading: Double
    var bottom: Double
    var trailing: Double

    init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    static let zero = LayoutInsets()

    var isZero: Bool { top == 0 && leading == 0 && bottom == 0 && trailing == 0 }
}

/// A named set of zones, optionally constrained to specific displays via
/// `displayPredicate`. In v1 the predicate is informational/grouping — zones
/// can be bound to hotkeys regardless of which display they were "designed for".
///
/// `outerMargin` insets the layout from the screen's visible frame (in display
/// points). `innerGap` is the symmetric gap between adjacent zones; each zone
/// is inset by `innerGap / 2` on every interior side (edges that touch the
/// layout boundary at 0 or 1 are not inset, so `outerMargin` alone controls
/// outer spacing).
struct Layout: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var zones: [Zone]
    var displayPredicate: DisplayPredicate
    var outerMargin: LayoutInsets
    var innerGap: Double

    init(id: UUID = UUID(),
         name: String,
         zones: [Zone],
         displayPredicate: DisplayPredicate = .anyDisplay,
         outerMargin: LayoutInsets = .zero,
         innerGap: Double = 0) {
        self.id = id
        self.name = name
        self.zones = zones
        self.displayPredicate = displayPredicate
        self.outerMargin = outerMargin
        self.innerGap = innerGap
    }

    // Custom decoding so layouts written before outerMargin/innerGap shipped
    // decode without migration.
    private enum CodingKeys: String, CodingKey {
        case id, name, zones, displayPredicate, outerMargin, innerGap
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.zones = try c.decode([Zone].self, forKey: .zones)
        self.displayPredicate = try c.decode(DisplayPredicate.self, forKey: .displayPredicate)
        self.outerMargin = try c.decodeIfPresent(LayoutInsets.self, forKey: .outerMargin) ?? .zero
        self.innerGap = try c.decodeIfPresent(Double.self, forKey: .innerGap) ?? 0
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

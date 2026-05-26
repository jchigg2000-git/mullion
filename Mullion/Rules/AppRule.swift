import Foundation

/// Explicit per-app placement preference. Overrides `LearnedPlacement`.
struct AppRule: Codable, Identifiable, Hashable {
    let id: UUID
    var bundleID: String
    var displayPredicate: DisplayPredicate
    var preferredZoneID: UUID
    var compatibilityProfile: CompatProfile

    init(id: UUID = UUID(),
         bundleID: String,
         displayPredicate: DisplayPredicate = .anyDisplay,
         preferredZoneID: UUID,
         compatibilityProfile: CompatProfile = .standard) {
        self.id = id
        self.bundleID = bundleID
        self.displayPredicate = displayPredicate
        self.preferredZoneID = preferredZoneID
        self.compatibilityProfile = compatibilityProfile
    }

    // Custom decode so legacy `app-rules.json` written before
    // `compatibilityProfile` existed still loads — defaults to `.standard`.
    private enum CodingKeys: String, CodingKey {
        case id, bundleID, displayPredicate, preferredZoneID, compatibilityProfile
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.bundleID = try c.decode(String.self, forKey: .bundleID)
        self.displayPredicate = try c.decode(DisplayPredicate.self, forKey: .displayPredicate)
        self.preferredZoneID = try c.decode(UUID.self, forKey: .preferredZoneID)
        self.compatibilityProfile = try c.decodeIfPresent(CompatProfile.self, forKey: .compatibilityProfile) ?? .standard
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

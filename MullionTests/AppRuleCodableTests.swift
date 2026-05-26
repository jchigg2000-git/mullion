import XCTest
@testable import Mullion

final class AppRuleCodableTests: XCTestCase {

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func test_decode_legacyRule_defaultsToStandardProfile() throws {
        // app-rules.json written before `compatibilityProfile` existed.
        let zoneID = UUID()
        let ruleID = UUID()
        let json = """
        {
          "id": "\(ruleID.uuidString)",
          "bundleID": "com.example.Legacy",
          "displayPredicate": { "anyDisplay": {} },
          "preferredZoneID": "\(zoneID.uuidString)"
        }
        """.data(using: .utf8)!

        let rule = try decoder.decode(AppRule.self, from: json)
        XCTAssertEqual(rule.id, ruleID)
        XCTAssertEqual(rule.bundleID, "com.example.Legacy")
        XCTAssertEqual(rule.preferredZoneID, zoneID)
        XCTAssertEqual(rule.compatibilityProfile, .standard)
    }

    func test_roundTrip_preservesAggressiveProfile() throws {
        let original = AppRule(
            bundleID: "com.microsoft.Excel",
            displayPredicate: .aspectRatioAtLeast(min: 2.0),
            preferredZoneID: UUID(),
            compatibilityProfile: .aggressive
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AppRule.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.compatibilityProfile, .aggressive)
    }

    func test_roundTrip_preservesSystemWindowManagerProfile() throws {
        // Phase G profile — kept in the data model so JSON survives a Phase
        // G rollout even if the user has been hand-editing files.
        let original = AppRule(
            bundleID: "com.apple.WebKit",
            preferredZoneID: UUID(),
            compatibilityProfile: .systemWindowManager
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AppRule.self, from: data)
        XCTAssertEqual(decoded.compatibilityProfile, .systemWindowManager)
    }

    func test_catalog_decodes_mixedLegacyAndNew() throws {
        let zoneID = UUID()
        // Catalog with one legacy entry and one new entry — version 1, two
        // rules. The decoder must handle both shapes in the same array.
        let json = """
        {
          "version": 1,
          "rules": [
            {
              "id": "\(UUID().uuidString)",
              "bundleID": "com.legacy.App",
              "displayPredicate": { "anyDisplay": {} },
              "preferredZoneID": "\(zoneID.uuidString)"
            },
            {
              "id": "\(UUID().uuidString)",
              "bundleID": "com.new.App",
              "displayPredicate": { "anyDisplay": {} },
              "preferredZoneID": "\(zoneID.uuidString)",
              "compatibilityProfile": "aggressive"
            }
          ]
        }
        """.data(using: .utf8)!

        let catalog = try decoder.decode(AppRuleCatalog.self, from: json)
        XCTAssertEqual(catalog.rules.count, 2)
        XCTAssertEqual(catalog.rules[0].compatibilityProfile, .standard)
        XCTAssertEqual(catalog.rules[1].compatibilityProfile, .aggressive)
    }
}

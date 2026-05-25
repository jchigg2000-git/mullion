import XCTest
@testable import Mullion

final class LayoutCodableTests: XCTestCase {

    func test_zone_roundTrip() throws {
        let zone = Zone(
            id: UUID(),
            name: "Top left",
            x: 0, y: 0, width: 0.333, height: 0.5,
            anchor: .topLeft
        )
        let data = try JSONEncoder().encode(zone)
        let decoded = try JSONDecoder().decode(Zone.self, from: data)
        XCTAssertEqual(zone, decoded)
    }

    func test_zone_withSizeOverride_roundTrip() throws {
        let zone = Zone(
            name: "Centered window",
            x: 0, y: 0, width: 1, height: 1,
            anchor: .center,
            sizeOverride: .init(width: 800, height: 600)
        )
        let data = try JSONEncoder().encode(zone)
        let decoded = try JSONDecoder().decode(Zone.self, from: data)
        XCTAssertEqual(zone, decoded)
    }

    func test_displayPredicate_anyDisplay_roundTrip() throws {
        let pred = DisplayPredicate.anyDisplay
        let data = try JSONEncoder().encode(pred)
        let decoded = try JSONDecoder().decode(DisplayPredicate.self, from: data)
        XCTAssertEqual(pred, decoded)
    }

    func test_displayPredicate_aspectRatio_roundTrip() throws {
        let pred = DisplayPredicate.aspectRatioAtLeast(min: 2.3)
        let data = try JSONEncoder().encode(pred)
        let decoded = try JSONDecoder().decode(DisplayPredicate.self, from: data)
        XCTAssertEqual(pred, decoded)
    }

    func test_displayPredicate_specificDisplay_roundTrip() throws {
        let pred = DisplayPredicate.specificDisplay(uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230")
        let data = try JSONEncoder().encode(pred)
        let decoded = try JSONDecoder().decode(DisplayPredicate.self, from: data)
        XCTAssertEqual(pred, decoded)
    }

    func test_displayPredicate_matches() {
        XCTAssertTrue(DisplayPredicate.anyDisplay.matches(uuid: "X", aspectRatio: 1.6))
        XCTAssertTrue(DisplayPredicate.aspectRatioAtLeast(min: 2.3).matches(uuid: "X", aspectRatio: 3.6))
        XCTAssertFalse(DisplayPredicate.aspectRatioAtLeast(min: 2.3).matches(uuid: "X", aspectRatio: 1.78))
        XCTAssertTrue(DisplayPredicate.specificDisplay(uuid: "A").matches(uuid: "A", aspectRatio: 1.0))
        XCTAssertFalse(DisplayPredicate.specificDisplay(uuid: "A").matches(uuid: "B", aspectRatio: 1.0))
    }

    func test_defaultLayouts_jsonInRepo_isValid() throws {
        // Read the bundled DefaultLayouts.json directly from the repo (the
        // resource isn't in the test bundle).
        let url = Bundle(for: type(of: self))
            .resourceURL!
            .deletingLastPathComponent()
            .appendingPathComponent("Mullion.app/Contents/Resources/DefaultLayouts.json")
        // Fall back to the in-source copy when running outside an Xcode build.
        let data: Data
        if let bundleData = try? Data(contentsOf: url) {
            data = bundleData
        } else {
            let repoURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Mullion/Resources/DefaultLayouts.json")
            data = try Data(contentsOf: repoURL)
        }
        let catalog = try JSONDecoder().decode(LayoutCatalog.self, from: data)
        XCTAssertGreaterThan(catalog.layouts.count, 0)
        XCTAssertEqual(catalog.version, 1)
        // Sanity: every zone has non-zero area.
        for layout in catalog.layouts {
            for zone in layout.zones {
                XCTAssertGreaterThan(zone.width, 0, "zone \(zone.name) has non-positive width")
                XCTAssertGreaterThan(zone.height, 0, "zone \(zone.name) has non-positive height")
            }
        }
    }

    func test_layoutCatalog_emptyDefault_encodes() throws {
        let catalog = LayoutCatalog(layouts: [])
        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(LayoutCatalog.self, from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertTrue(decoded.layouts.isEmpty)
    }

    func test_appRule_roundTrip() throws {
        let rule = AppRule(
            bundleID: "com.tinyspeck.slackmacgap",
            displayPredicate: .aspectRatioAtLeast(min: 2.3),
            preferredZoneID: UUID()
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(AppRule.self, from: data)
        XCTAssertEqual(rule, decoded)
    }

    func test_hotkeyBinding_singleTarget_roundTrip() throws {
        let binding = HotkeyBinding(
            shortcutName: "snapLeftHalf",
            targets: [UUID()],
            role: .snap
        )
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: data)
        XCTAssertEqual(binding, decoded)
    }

    func test_hotkeyBinding_cycleTargets_preservesOrder() throws {
        let ids = [UUID(), UUID(), UUID()]
        let binding = HotkeyBinding(shortcutName: "cycleLeft", targets: ids, role: .snap)
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: data)
        XCTAssertEqual(decoded.targets, ids)
    }
}

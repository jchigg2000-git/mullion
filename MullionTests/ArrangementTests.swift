import XCTest
@testable import Mullion

@MainActor
final class ArrangementTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mullion-arrangements-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    // MARK: DisplaySig.bucket

    func test_bucket_rounds_to_nearest_10pt() {
        XCTAssertEqual(DisplaySig.bucket(0), 0)
        XCTAssertEqual(DisplaySig.bucket(4), 0)        // < 5 rounds down
        XCTAssertEqual(DisplaySig.bucket(5), 10)       // half-up via .rounded()
        XCTAssertEqual(DisplaySig.bucket(14.9), 10)
        XCTAssertEqual(DisplaySig.bucket(3439), 3440)
        XCTAssertEqual(DisplaySig.bucket(3440), 3440)
        XCTAssertEqual(DisplaySig.bucket(-12), -10)
        XCTAssertEqual(DisplaySig.bucket(-15), -20)    // -15 rounds away-from-zero
    }

    func test_currentSignature_isCanonicalSorted_byUUID() {
        // canonical() is order-independent, so two arrangements built from
        // the same physical setup match regardless of NSScreen.screens order.
        let a = DisplaySig(displayUUID: "B-uuid", widthPoints: 3440, heightPoints: 1440, originX: 0, originY: 0)
        let b = DisplaySig(displayUUID: "A-uuid", widthPoints: 1920, heightPoints: 1080, originX: 3440, originY: 0)
        let canonical = Arrangement.canonical([a, b])
        XCTAssertEqual(canonical.map(\.displayUUID), ["A-uuid", "B-uuid"])
    }

    // MARK: Arrangement init — canonical signature

    func test_init_canonicalises_signature_so_equality_is_order_independent() {
        let s1 = DisplaySig(displayUUID: "u1", widthPoints: 100, heightPoints: 100, originX: 0, originY: 0)
        let s2 = DisplaySig(displayUUID: "u2", widthPoints: 200, heightPoints: 200, originX: 100, originY: 0)
        let id = UUID()
        let a = Arrangement(id: id, name: "Home", signature: [s1, s2])
        let b = Arrangement(id: id, name: "Home", signature: [s2, s1])
        XCTAssertEqual(a, b)
    }

    // MARK: ArrangementStore — CRUD + match

    func test_store_upsert_and_match_returnsArrangementWithMatchingSignature() {
        let store = ArrangementStore(url: tempURL)
        let sig = [
            DisplaySig(displayUUID: "ultrawide", widthPoints: 3440, heightPoints: 1440, originX: 0, originY: 0)
        ]
        let arrangement = Arrangement(name: "Office", signature: sig, defaultLayoutID: UUID())
        store.upsert(arrangement)

        let matched = store.arrangement(matching: sig)
        XCTAssertEqual(matched?.id, arrangement.id)
    }

    func test_store_match_isOrderIndependent() {
        let store = ArrangementStore(url: tempURL)
        let a = DisplaySig(displayUUID: "u-a", widthPoints: 3440, heightPoints: 1440, originX: 0, originY: 0)
        let b = DisplaySig(displayUUID: "u-b", widthPoints: 1920, heightPoints: 1080, originX: 3440, originY: 200)
        store.upsert(Arrangement(name: "Two", signature: [a, b]))

        // Query in reversed order — exact-match should still hit because
        // arrangement() canonicalises the query.
        let matched = store.arrangement(matching: [b, a])
        XCTAssertEqual(matched?.name, "Two")
    }

    func test_store_match_returnsNil_whenNoArrangementMatches() {
        let store = ArrangementStore(url: tempURL)
        store.upsert(Arrangement(
            name: "Single",
            signature: [DisplaySig(displayUUID: "u", widthPoints: 100, heightPoints: 100, originX: 0, originY: 0)]
        ))

        let other = [DisplaySig(displayUUID: "other-uuid", widthPoints: 100, heightPoints: 100, originX: 0, originY: 0)]
        XCTAssertNil(store.arrangement(matching: other))
    }

    func test_store_remove_dropsArrangement() {
        let store = ArrangementStore(url: tempURL)
        let arrangement = Arrangement(
            name: "ToRemove",
            signature: [DisplaySig(displayUUID: "x", widthPoints: 1, heightPoints: 1, originX: 0, originY: 0)]
        )
        store.upsert(arrangement)
        XCTAssertEqual(store.arrangements.count, 1)

        store.remove(arrangementWithID: arrangement.id)
        XCTAssertTrue(store.arrangements.isEmpty)
    }

    // MARK: Catalog roundtrip

    func test_catalog_jsonRoundtrip_preservesArrangementsAndDefaultLayoutID() throws {
        let layoutID = UUID()
        let original = ArrangementCatalog(arrangements: [
            Arrangement(
                name: "Home",
                signature: [
                    DisplaySig(displayUUID: "u-1", widthPoints: 3440, heightPoints: 1440, originX: 0, originY: 0),
                    DisplaySig(displayUUID: "u-2", widthPoints: 1920, heightPoints: 1080, originX: 3440, originY: 0)
                ],
                defaultLayoutID: layoutID
            )
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ArrangementCatalog.self, from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.arrangements.count, 1)
        XCTAssertEqual(decoded.arrangements[0].name, "Home")
        XCTAssertEqual(decoded.arrangements[0].defaultLayoutID, layoutID)
        XCTAssertEqual(decoded.arrangements[0].signature.count, 2)
    }

    func test_catalog_decode_nullDefaultLayoutID_yieldsNil() throws {
        let json = """
        {
          "version": 1,
          "arrangements": [
            {
              "id": "\(UUID().uuidString)",
              "name": "NoDefault",
              "signature": [
                {
                  "displayUUID": "u",
                  "widthPoints": 100,
                  "heightPoints": 100,
                  "originX": 0,
                  "originY": 0
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let catalog = try JSONDecoder().decode(ArrangementCatalog.self, from: json)
        XCTAssertNil(catalog.arrangements[0].defaultLayoutID)
    }
}

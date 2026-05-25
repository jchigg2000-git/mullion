import XCTest
@testable import Mullion

final class JSONStoreTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mullion-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    struct Model: Codable, Equatable {
        var name: String
        var count: Int
    }

    func test_loadsDefault_whenFileDoesNotExist() {
        let store = JSONStore(url: tempURL, default: Model(name: "fresh", count: 0))
        XCTAssertEqual(store.value, Model(name: "fresh", count: 0))
    }

    func test_flush_writesToDisk() throws {
        let store = JSONStore(url: tempURL, default: Model(name: "x", count: 1))
        store.update { $0.count = 42 }
        store.flush()

        let data = try Data(contentsOf: tempURL)
        let reloaded = try JSONDecoder().decode(Model.self, from: data)
        XCTAssertEqual(reloaded.count, 42)
    }

    func test_loadsExistingFile_onInit() throws {
        let initial = Model(name: "existing", count: 7)
        let data = try JSONEncoder().encode(initial)
        try data.write(to: tempURL)

        let store = JSONStore(url: tempURL, default: Model(name: "wrong", count: 0))
        XCTAssertEqual(store.value, initial)
    }

    func test_reload_picksUpExternalChanges() throws {
        let store = JSONStore(url: tempURL, default: Model(name: "v1", count: 0))
        store.flush()

        // Simulate external edit
        let externalEdit = Model(name: "edited externally", count: 99)
        let data = try JSONEncoder().encode(externalEdit)
        try data.write(to: tempURL)

        store.reload()
        XCTAssertEqual(store.value, externalEdit)
    }

    func test_replace_overwritesValue() {
        let store = JSONStore(url: tempURL, default: Model(name: "v1", count: 0))
        store.replace(Model(name: "v2", count: 10))
        XCTAssertEqual(store.value, Model(name: "v2", count: 10))
    }
}

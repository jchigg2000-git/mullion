import XCTest
@testable import Mullion

@MainActor
final class JSONStoreTests: XCTestCase {

    private var tempDir: URL!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        // A directory of our own: the backup tests list it for copies.
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mullion-test-\(UUID().uuidString)", isDirectory: true)
        tempURL = tempDir.appendingPathComponent("store.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
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
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
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

    // MARK: Unreadable files are never silently overwritten

    private func backups() -> [URL] {
        let prefix = tempURL.lastPathComponent + ".unreadable-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) }.map { tempDir.appendingPathComponent($0) }
    }

    /// Regression: a layouts.json with a stray comma decoded to nothing, the
    /// store fell back to defaults, and the next edit overwrote the file with
    /// them, destroying the user's hand-written config.
    func test_unreadableFileOnInit_isCopiedAsideBeforeTheNextWrite() throws {
        let broken = Data(#"{ "name": "mine", "count": 3"#.utf8)  // truncated
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try broken.write(to: tempURL)

        let store = JSONStore(url: tempURL, default: Model(name: "defaults", count: 0))
        XCTAssertEqual(store.value, Model(name: "defaults", count: 0))
        XCTAssertTrue(backups().isEmpty, "reading alone must not write anything")

        store.update { $0.count = 1 }
        store.flush()

        let saved = try XCTUnwrap(backups().first)
        XCTAssertEqual(backups().count, 1)
        XCTAssertEqual(try Data(contentsOf: saved), broken)
        XCTAssertEqual(try JSONDecoder().decode(Model.self, from: Data(contentsOf: tempURL)).count, 1)

        // Later writes have nothing new to preserve.
        store.update { $0.count = 2 }
        store.flush()
        XCTAssertEqual(backups().count, 1)
    }

    func test_unreadableFileAfterReload_keepsMemoryAndIsCopiedAsideOnWrite() throws {
        let store = JSONStore(url: tempURL, default: Model(name: "v1", count: 5))
        store.flush()
        let broken = Data("not json at all".utf8)
        try broken.write(to: tempURL)

        store.reload()
        XCTAssertEqual(store.value, Model(name: "v1", count: 5), "a failed reload keeps what we had")

        store.update { $0.count = 6 }
        store.flush()
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups().first)), broken)
    }

    func test_fixedFile_isNotCopiedAside() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data("oops".utf8).write(to: tempURL)
        let store = JSONStore(url: tempURL, default: Model(name: "d", count: 0))
        // The user repairs the file before anything is written.
        try JSONEncoder().encode(Model(name: "fixed", count: 9)).write(to: tempURL)
        store.reload()
        XCTAssertEqual(store.value, Model(name: "fixed", count: 9))

        store.update { $0.count = 10 }
        store.flush()
        XCTAssertTrue(backups().isEmpty)
    }

    func test_emptyFile_isNotWorthKeeping() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data().write(to: tempURL)
        let store = JSONStore(url: tempURL, default: Model(name: "d", count: 0))
        store.update { $0.count = 1 }
        store.flush()
        XCTAssertTrue(backups().isEmpty)
    }

    // MARK: Flush on quit

    /// Regression: nothing flushed on quit, so an edit made within the 500 ms
    /// debounce before quitting was lost.
    func test_flushIfPending_writesAnEditStillInsideTheDebounce() throws {
        let store = JSONStore(url: tempURL, default: Model(name: "d", count: 0), debounce: 60)
        store.update { $0.count = 7 }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))

        store.flushIfPending()
        XCTAssertEqual(try JSONDecoder().decode(Model.self, from: Data(contentsOf: tempURL)).count, 7)
    }

    func test_flushIfPending_leavesAnUntouchedFileAlone() throws {
        // A hand-edit the file watcher has not reloaded yet must survive quit.
        let store = JSONStore(url: tempURL, default: Model(name: "d", count: 0), debounce: 60)
        store.flush()
        let edited = Model(name: "hand edit", count: 42)
        try JSONEncoder().encode(edited).write(to: tempURL)

        store.flushIfPending()
        XCTAssertEqual(try JSONDecoder().decode(Model.self, from: Data(contentsOf: tempURL)), edited)
    }

    func test_flushIfPending_isANoOpOnceTheDebouncedWriteHasRun() throws {
        let store = JSONStore(url: tempURL, default: Model(name: "d", count: 0), debounce: 0.01)
        store.update { $0.count = 3 }
        let written = expectation(description: "debounced write lands")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { written.fulfill() }
        wait(for: [written], timeout: 2)
        XCTAssertEqual(try JSONDecoder().decode(Model.self, from: Data(contentsOf: tempURL)).count, 3)

        let edited = Model(name: "hand edit", count: 42)
        try JSONEncoder().encode(edited).write(to: tempURL)
        store.flushIfPending()
        XCTAssertEqual(try JSONDecoder().decode(Model.self, from: Data(contentsOf: tempURL)), edited)
    }

    func test_replace_overwritesValue() {
        let store = JSONStore(url: tempURL, default: Model(name: "v1", count: 0))
        store.replace(Model(name: "v2", count: 10))
        XCTAssertEqual(store.value, Model(name: "v2", count: 10))
    }
}

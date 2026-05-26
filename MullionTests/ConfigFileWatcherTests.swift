import XCTest
@testable import Mullion

final class ConfigFileWatcherTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mullion-watcher-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func test_debounces_burstOfScheduleFire_intoSingleCallback() {
        // Coalescing matters: atomic writes (`JSONStore.flush`) produce a
        // burst of FSEvents on the temp + rename pair, and we want one
        // reload-all per save, not many.
        var callCount = 0
        let expectation = expectation(description: "callback fires once")
        guard let watcher = ConfigFileWatcher(
            directory: directory,
            debounceInterval: 0.10,
            onChange: {
                callCount += 1
                expectation.fulfill()
            }
        ) else {
            XCTFail("FSEventStream failed to mount")
            return
        }

        for _ in 0..<20 {
            watcher.scheduleFire()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(callCount, 1)
    }
}

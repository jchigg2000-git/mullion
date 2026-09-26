import CoreServices
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

    func test_snapHistoryWrites_doNotTriggerReload() {
        // Regression: every snap writes window-history.json (atomically, via
        // a temp file + rename), and that write reloaded every store and
        // re-registered every hotkey ~0.8s after the snap.
        let dir = "/Users/x/Library/Application Support/Mullion"
        XCTAssertFalse(ConfigFileWatcher.shouldReload(forChangedPaths: [
            "\(dir)/.dat.nosync3f1a.Hx2QpL",
            "\(dir)/window-history.json",
        ]))
        XCTAssertFalse(ConfigFileWatcher.shouldReload(forChangedPaths: [
            "\(dir)/layouts.json.bak-20260910-212805",
        ]))
        XCTAssertTrue(ConfigFileWatcher.shouldReload(forChangedPaths: [
            "\(dir)/.dat.nosync3f1a.Hx2QpL",
            "\(dir)/layouts.json",
        ]))
        XCTAssertTrue(ConfigFileWatcher.shouldReload(forChangedPaths: []))
    }

    func test_rescanNoticeOrDirectoryEvent_triggersReload() {
        // Regression: the name filter ignored events carrying only the
        // watched directory's path, so a config edit hidden in an FSEvents
        // drop (MustScanSubDirs|UserDropped) or a config dir swapped into
        // place by a restore was never applied.
        let dir = "/Users/x/Library/Application Support/Mullion"
        let dropped = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
        )
        XCTAssertTrue(ConfigFileWatcher.shouldReload(
            forChangedPaths: [dir], flags: [dropped], watchedDirectory: dir
        ))
        let renamedDir = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemRenamed
        )
        XCTAssertTrue(ConfigFileWatcher.shouldReload(
            forChangedPaths: [dir], flags: [renamedDir], watchedDirectory: dir
        ))
        // A snap's history write still doesn't reload.
        let fileRenamed = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemIsFile | kFSEventStreamEventFlagItemRenamed
        )
        XCTAssertFalse(ConfigFileWatcher.shouldReload(
            forChangedPaths: ["\(dir)/window-history.json"],
            flags: [fileRenamed],
            watchedDirectory: dir
        ))
    }
}

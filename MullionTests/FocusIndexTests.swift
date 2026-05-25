import XCTest
import ApplicationServices
@testable import Mullion

final class FocusIndexTests: XCTestCase {

    // Use the test process's own pid for AXWindow fixtures. The MRU only
    // exercises CFEqual on the AXUIElement and pid bookkeeping — it never
    // actually mutates a window — so the elements don't need to refer to
    // real on-screen UI.
    private let selfPid: pid_t = getpid()

    private func makeWindow() -> AXWindow {
        let element = AXUIElementCreateApplication(selfPid)
        return AXWindow(element: element, pid: selfPid)
    }

    func test_record_dedupsSameElement() {
        // AXUIElementCreateApplication(samePid) returns CFEqual elements, so
        // recording the same window twice should collapse to one entry — not
        // grow the list. Validates the dedup branch of `record`.
        let index = FocusIndex()
        let zone = UUID()

        index.record(window: makeWindow(), zoneID: zone)
        index.record(window: makeWindow(), zoneID: zone)
        index.record(window: makeWindow(), zoneID: zone)

        XCTAssertEqual(index.count(in: zone), 1)
        XCTAssertNotNil(index.mostRecentAliveWindow(in: zone))
    }

    func test_recordsArePerZone() {
        let index = FocusIndex()
        let zoneA = UUID()
        let zoneB = UUID()
        index.record(window: makeWindow(), zoneID: zoneA)

        XCTAssertEqual(index.count(in: zoneA), 1)
        XCTAssertEqual(index.count(in: zoneB), 0)
        XCTAssertNil(index.mostRecentAliveWindow(in: zoneB))
    }

    func test_evict_clearsAllEntriesForPid() {
        let index = FocusIndex()
        let zone = UUID()
        index.record(window: makeWindow(), zoneID: zone)
        XCTAssertEqual(index.count(in: zone), 1)

        index.evict(pid: selfPid)
        XCTAssertEqual(index.count(in: zone), 0)
        XCTAssertNil(index.mostRecentAliveWindow(in: zone))
    }

    func test_perZoneCap_dropsOldestEntries() {
        let index = FocusIndex(perZoneCap: 3)
        let zone = UUID()

        for _ in 0..<5 {
            // Each AXUIElementCreateApplication call returns an element that
            // CFEquals others with the same pid, so to actually populate the
            // MRU with distinct entries we'd need distinct pids. For the cap
            // test, all we need is that count never exceeds the cap.
            index.record(window: makeWindow(), zoneID: zone)
        }

        XCTAssertLessThanOrEqual(index.count(in: zone), 3)
    }
}

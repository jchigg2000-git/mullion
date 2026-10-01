import XCTest
import ApplicationServices
@testable import Mullion

/// Regression cover for drag-to-snap and grid clicks, which recorded the
/// learned placement but never the per-zone focus MRU, so the zone's `.focus`
/// hotkey could not find a window placed by mouse.
@MainActor
final class SnapRecorderTests: XCTestCase {

    private let selfPid: pid_t = getpid()

    private func window() -> AXWindow {
        AXWindow(element: AXUIElementCreateApplication(selfPid), pid: selfPid)
    }

    private func historyStore() -> WindowHistoryStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("window-history-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return WindowHistoryStore(url: url)
    }

    func test_record_leavesBothALearnedPlacementAndAFocusEntry() {
        let history = historyStore()
        let focus = FocusIndex()
        let zone = UUID()

        SnapRecorder(history: history, focusIndex: focus)
            .record(window: window(), bundleID: "com.example.app", screenUUID: "display-1", zoneID: zone)

        XCTAssertEqual(history.placement(bundleID: "com.example.app", displayUUID: "display-1")?.zoneID, zone)
        XCTAssertEqual(focus.count(in: zone), 1)
        XCTAssertNotNil(focus.mostRecentAliveWindow(in: zone))
    }

    func test_record_withoutABundleID_stillFeedsTheFocusIndex() {
        let history = historyStore()
        let focus = FocusIndex()
        let zone = UUID()

        SnapRecorder(history: history, focusIndex: focus)
            .record(window: window(), bundleID: nil, screenUUID: "display-1", zoneID: zone)

        XCTAssertTrue(history.placements.isEmpty)
        XCTAssertEqual(focus.count(in: zone), 1)
    }

    func test_record_toleratesMissingCollaborators() {
        let zone = UUID()
        SnapRecorder(history: nil, focusIndex: nil)
            .record(window: window(), bundleID: "com.example.app", screenUUID: "display-1", zoneID: zone)
    }
}

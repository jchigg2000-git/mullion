import XCTest
import ApplicationServices
@testable import Mullion

/// Regression cover for drag-to-snap's window lookup, which ran an AX
/// hit-test on every left click system-wide from inside the mouse event
/// tap's callback — the stall that got the tap disabled by timeout.
@MainActor
final class DragOverlayControllerTests: XCTestCase {

    private var lookups: [CGPoint] = []

    private func tempURL(_ name: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(name)-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Default settings: drag-snap modifier is ⌃. No layouts, so no overlay
    /// windows are created and no snap can happen.
    private func controller() -> DragOverlayController {
        let pid = getpid()
        return DragOverlayController(
            layoutStore: LayoutStore(url: tempURL("layouts"), defaults: []),
            settingsStore: SettingsStore(url: tempURL("settings")),
            appRuleStore: AppRuleStore(url: tempURL("app-rules")),
            historyStore: WindowHistoryStore(url: tempURL("window-history")),
            windowAtPoint: { [unowned self] point in
                self.lookups.append(point)
                return AXWindow(element: AXUIElementCreateApplication(pid), pid: pid)
            }
        )
    }

    func test_ordinaryClick_doesNoWindowLookup() {
        let drag = controller()
        drag.handleMouseDown(at: CGPoint(x: 10, y: 10), flags: [])
        drag.handleMouseUp(at: CGPoint(x: 10, y: 10), flags: [])
        XCTAssertEqual(lookups, [])
    }

    func test_ordinaryDrag_withoutModifier_doesNoWindowLookup() {
        let drag = controller()
        drag.handleMouseDown(at: CGPoint(x: 10, y: 10), flags: [])
        drag.handleMouseDragged(at: CGPoint(x: 40, y: 10), flags: [])
        drag.handleMouseUp(at: CGPoint(x: 40, y: 10), flags: [])
        XCTAssertEqual(lookups, [])
    }

    func test_modifiedPress_looksUpTheWindowUnderThePress() {
        let drag = controller()
        drag.handleMouseDown(at: CGPoint(x: 10, y: 10), flags: .maskControl)
        XCTAssertEqual(lookups, [CGPoint(x: 10, y: 10)])
    }

    func test_modifierAddedMidDrag_looksUpOnceAtTheCursor() {
        let drag = controller()
        drag.handleMouseDown(at: CGPoint(x: 10, y: 10), flags: [])
        drag.handleMouseDragged(at: CGPoint(x: 50, y: 20), flags: .maskControl)
        drag.handleMouseDragged(at: CGPoint(x: 90, y: 30), flags: .maskControl)
        XCTAssertEqual(lookups, [CGPoint(x: 50, y: 20)])
        drag.handleMouseUp(at: CGPoint(x: 90, y: 30), flags: .maskControl)
        // The next modified drag without a press is not a drag at all.
        drag.handleMouseDragged(at: CGPoint(x: 95, y: 30), flags: .maskControl)
        XCTAssertEqual(lookups.count, 1)
    }
}

import CoreGraphics
import XCTest
@testable import Mullion

@MainActor
final class MouseEventTapTests: XCTestCase {

    func test_tapDisabledNotices_reenableTheTap() {
        // Regression: the callback ignored macOS's one-time "tap disabled"
        // notice, so a timeout during a display reconfiguration silenced
        // drag-to-snap and the grid until Mullion was relaunched.
        XCTAssertEqual(MouseEventTap.disposition(for: .tapDisabledByTimeout), .reenable)
        XCTAssertEqual(MouseEventTap.disposition(for: .tapDisabledByUserInput), .reenable)
        XCTAssertEqual(MouseEventTap.disposition(for: .leftMouseDown), .dispatch)
        XCTAssertEqual(MouseEventTap.disposition(for: .flagsChanged), .dispatch)
        XCTAssertEqual(MouseEventTap.disposition(for: .rightMouseDown), .ignore)
    }

    func test_resyncModifiers_redeliversLiveFlags_soAMissedReleaseHidesTheGrid() {
        // Regression: while the tap was disabled, a modifier release was never
        // delivered, so the grid stayed painted until the next click. Re-arming
        // the tap now re-delivers the modifier state the OS reports.
        let tap = MouseEventTap()
        var delivered: [CGEventFlags] = []
        tap.onFlagsChanged = { delivered.append($0) }

        tap.currentFlags = { [] }
        tap.resyncModifiers()
        tap.currentFlags = { [.maskControl, .maskAlternate] }
        tap.resyncModifiers()

        XCTAssertEqual(delivered, [[], [.maskControl, .maskAlternate]])
        // Fed to the settings gate, the first is a release and the second a press.
        XCTAssertFalse(ModifierMask.controlOption.isSatisfied(by: delivered[0]))
        XCTAssertTrue(ModifierMask.controlOption.isSatisfied(by: delivered[1]))
    }
}

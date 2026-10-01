import CoreGraphics
import XCTest
@testable import Mullion

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
}

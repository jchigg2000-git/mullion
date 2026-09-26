import XCTest
@testable import Mullion

final class ZoneHitTestTests: XCTestCase {

    private let layout = Layout(
        name: "Halves",
        zones: [
            Zone(name: "left", x: 0, y: 0, width: 0.5, height: 1),
            Zone(name: "right", x: 0.5, y: 0, width: 0.5, height: 1),
        ]
    )

    func test_displayMovedUnderSameUUID_clickResolvesAgainstNewFrame() {
        // Regression: after a dock/undock the grid resolved clicks against
        // an NSScreen captured when its panel was first built, so a display
        // whose frame moved while keeping its UUID snapped into the wrong
        // zone or nothing. Resolution must follow the frame live *now*.
        // A 1512×950 built-in visible frame sat right of a 2560-wide
        // primary, then moved left of it after a redock.
        let before = CGRect(x: 2560, y: -479, width: 1512, height: 950)
        let after = CGRect(x: -1512, y: 0, width: 1512, height: 950)
        let clickInNewLeftHalf = CGPoint(x: -1400, y: 400)

        XCTAssertEqual(
            ZoneHitTest.zoneIndex(at: clickInNewLeftHalf, in: layout, visibleFrame: after),
            0
        )
        XCTAssertNil(
            ZoneHitTest.zoneIndex(at: clickInNewLeftHalf, in: layout, visibleFrame: before)
        )
        XCTAssertEqual(
            ZoneHitTest.zoneIndex(at: CGPoint(x: -100, y: 400), in: layout, visibleFrame: after),
            1
        )
    }
}

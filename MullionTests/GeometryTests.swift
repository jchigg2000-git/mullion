import XCTest
@testable import Mullion

final class GeometryTests: XCTestCase {

    // MARK: - flipY

    func test_flipY_singleDisplay_topLeftCorner() {
        // Primary 1920×1080 at origin. Window in upper-left of AppKit:
        // AppKit y=1080-100=980 (bottom of the window), height 100 → top at 1080.
        let appKit = CGRect(x: 0, y: 980, width: 200, height: 100)
        let ax = Geometry.flipY(appKit, originScreenMaxY: 1080)
        XCTAssertEqual(ax, CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    func test_flipY_singleDisplay_bottomLeftCorner() {
        // Window pinned to bottom of AppKit (y=0).
        let appKit = CGRect(x: 0, y: 0, width: 200, height: 100)
        let ax = Geometry.flipY(appKit, originScreenMaxY: 1080)
        XCTAssertEqual(ax, CGRect(x: 0, y: 980, width: 200, height: 100))
    }

    func test_flipY_isSelfInverse() {
        let appKit = CGRect(x: 100, y: 200, width: 300, height: 400)
        let ax = Geometry.flipY(appKit, originScreenMaxY: 1080)
        let roundtrip = Geometry.flipY(ax, originScreenMaxY: 1080)
        XCTAssertEqual(appKit, roundtrip)
    }

    func test_flipY_negativeXSecondaryDisplay_yIsRelativeToOrigin() {
        // Two-display arrangement: secondary to the LEFT of primary.
        // Secondary is 1920×1080 at AppKit origin (-1920, 0). Primary is
        // 1920×1080 at (0, 0). Origin-screen maxY is 1080 (primary).
        // A window at AppKit (-1500, 540, 800, 540) — upper region of the
        // secondary display — should AX-convert with x stays negative,
        // y = 1080 - (540 + 540) = 0.
        let appKit = CGRect(x: -1500, y: 540, width: 800, height: 540)
        let ax = Geometry.flipY(appKit, originScreenMaxY: 1080)
        XCTAssertEqual(ax, CGRect(x: -1500, y: 0, width: 800, height: 540))
    }

    func test_flipY_negativeYSecondaryDisplay_yGoesPositiveInAX() {
        // Secondary 1920×1080 sitting ABOVE the primary at AppKit origin
        // (0, 1080). Primary is 1920×1080 at origin (0, 0). Origin maxY = 1080.
        // A window mid-secondary at AppKit (100, 1300, 400, 300) →
        // AX y = 1080 - (1300 + 300) = -520. AX uses negative y for
        // displays positioned above the primary; that's correct.
        let appKit = CGRect(x: 100, y: 1300, width: 400, height: 300)
        let ax = Geometry.flipY(appKit, originScreenMaxY: 1080)
        XCTAssertEqual(ax, CGRect(x: 100, y: -520, width: 400, height: 300))
    }

    // MARK: - indexOfScreen

    func test_indexOfScreen_singleDisplay_containsRect() {
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        let rect = CGRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertEqual(Geometry.indexOfScreen(containingAppKitRect: rect, in: screens), 0)
    }

    func test_indexOfScreen_twoDisplays_picksLargerIntersection() {
        // Two side-by-side displays. A window mostly on the right one.
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 1920, height: 1080),
        ]
        // Window spans the boundary, 80% on the right display.
        let rect = CGRect(x: 1500, y: 100, width: 1200, height: 600)
        XCTAssertEqual(Geometry.indexOfScreen(containingAppKitRect: rect, in: screens), 1)
    }

    func test_indexOfScreen_returnsNilIfNoIntersection() {
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        let rect = CGRect(x: 5000, y: 5000, width: 100, height: 100)
        XCTAssertNil(Geometry.indexOfScreen(containingAppKitRect: rect, in: screens))
    }

    func test_indexOfScreen_negativeArrangement_leftSecondary() {
        // Secondary to the LEFT of primary (negative x).
        let screens = [
            CGRect(x: -1920, y: 0, width: 1920, height: 1080),  // secondary
            CGRect(x: 0, y: 0, width: 1920, height: 1080),       // primary
        ]
        let rect = CGRect(x: -1000, y: 500, width: 400, height: 300)
        XCTAssertEqual(Geometry.indexOfScreen(containingAppKitRect: rect, in: screens), 0)
    }

    func test_indexOfScreen_fourCornerArrangement() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),         // primary
            CGRect(x: 1920, y: 0, width: 1920, height: 1080),      // right
            CGRect(x: 0, y: 1080, width: 1920, height: 1080),      // top
            CGRect(x: 1920, y: 1080, width: 1920, height: 1080),   // upper-right
        ]
        let rect = CGRect(x: 2000, y: 1500, width: 400, height: 300)
        XCTAssertEqual(Geometry.indexOfScreen(containingAppKitRect: rect, in: screens), 3)
    }
}

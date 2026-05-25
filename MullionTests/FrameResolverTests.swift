import XCTest
@testable import Mullion

final class FrameResolverTests: XCTestCase {

    // 1920×1080 display at AppKit origin (0,0). visibleFrame == frame for the test fixture.
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func test_leftHalf_anchoredTopLeft() {
        let zone = Zone(name: "L", x: 0, y: 0, width: 0.5, height: 1, anchor: .topLeft)
        let rect = FrameResolver.appKitFrame(for: zone, in: visibleFrame)
        // Left half: AppKit origin (0, 0), size (960, 1080).
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 960, height: 1080))
    }

    func test_topHalf_userY0_topHalfInAppKit() {
        // User says "top half" = y:0 height:0.5. In AppKit that's the upper
        // half: origin.y = 540, height = 540.
        let zone = Zone(name: "T", x: 0, y: 0, width: 1, height: 0.5, anchor: .topLeft)
        let rect = FrameResolver.appKitFrame(for: zone, in: visibleFrame)
        XCTAssertEqual(rect, CGRect(x: 0, y: 540, width: 1920, height: 540))
    }

    func test_bottomHalf_userY05() {
        // User y:0.5 height:0.5 = bottom half. AppKit y starts at 0.
        let zone = Zone(name: "B", x: 0, y: 0.5, width: 1, height: 0.5, anchor: .topLeft)
        let rect = FrameResolver.appKitFrame(for: zone, in: visibleFrame)
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 1920, height: 540))
    }

    func test_sixPaneTopLeft() {
        // 3 cols × 2 rows. Top-left cell.
        let zone = Zone(name: "TL", x: 0, y: 0, width: 0.333, height: 0.5, anchor: .topLeft)
        let rect = FrameResolver.appKitFrame(for: zone, in: visibleFrame)
        XCTAssertEqual(rect.origin.x, 0, accuracy: 0.01)
        XCTAssertEqual(rect.origin.y, 540, accuracy: 0.01)
        XCTAssertEqual(rect.size.width, 639.36, accuracy: 0.01)
        XCTAssertEqual(rect.size.height, 540, accuracy: 0.01)
    }

    func test_sixPaneBottomRight() {
        let zone = Zone(name: "BR", x: 0.667, y: 0.5, width: 0.333, height: 0.5, anchor: .topLeft)
        let rect = FrameResolver.appKitFrame(for: zone, in: visibleFrame)
        XCTAssertEqual(rect.origin.x, 1280.64, accuracy: 0.01)
        XCTAssertEqual(rect.origin.y, 0, accuracy: 0.01)
        XCTAssertEqual(rect.size.width, 639.36, accuracy: 0.01)
        XCTAssertEqual(rect.size.height, 540, accuracy: 0.01)
    }

    func test_quarterHalfQuarter_centerZone() {
        // 1/4 - 1/2 - 1/4 split, center zone (full height).
        let zone = Zone(name: "C", x: 0.25, y: 0, width: 0.5, height: 1, anchor: .topLeft)
        let rect = FrameResolver.appKitFrame(for: zone, in: visibleFrame)
        XCTAssertEqual(rect, CGRect(x: 480, y: 0, width: 960, height: 1080))
    }

    func test_visibleFrameWithMenuBarOffset_yMath() {
        // Real visibleFrame on a 1920×1080 display with menu bar is roughly
        // (0, 0, 1920, 1055). Test that the top-half zone still computes
        // relative to visibleFrame, not the absolute display frame.
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1055)
        let zone = Zone(name: "T", x: 0, y: 0, width: 1, height: 0.5, anchor: .topLeft)
        let rect = FrameResolver.appKitFrame(for: zone, in: visible)
        XCTAssertEqual(rect.origin.y, 527.5, accuracy: 0.01)
        XCTAssertEqual(rect.size.height, 527.5, accuracy: 0.01)
    }

    func test_sizeOverride_centerAnchor_centersWindow() {
        // Zone fills the screen but window is pinned at 800×600 centered.
        let zone = Zone(
            name: "Centered",
            x: 0, y: 0, width: 1, height: 1,
            anchor: .center,
            sizeOverride: .init(width: 800, height: 600)
        )
        let rect = FrameResolver.appKitFrame(for: zone, in: visibleFrame)
        XCTAssertEqual(rect.origin.x, 560, accuracy: 0.01)  // (1920 - 800)/2
        XCTAssertEqual(rect.origin.y, 240, accuracy: 0.01)  // (1080 - 600)/2
        XCTAssertEqual(rect.size.width, 800, accuracy: 0.01)
        XCTAssertEqual(rect.size.height, 600, accuracy: 0.01)
    }

    func test_sizeOverride_topLeftAnchor() {
        let zone = Zone(
            name: "Pinned TL",
            x: 0, y: 0, width: 0.5, height: 0.5,
            anchor: .topLeft,
            sizeOverride: .init(width: 400, height: 300)
        )
        let rect = FrameResolver.appKitFrame(for: zone, in: visibleFrame)
        // Zone frame in AppKit: x:0 y:540 w:960 h:540. Pin window to TL of zone.
        XCTAssertEqual(rect.origin.x, 0, accuracy: 0.01)
        XCTAssertEqual(rect.origin.y, 540 + 540 - 300, accuracy: 0.01)  // top of zone, minus window height
        XCTAssertEqual(rect.size.width, 400, accuracy: 0.01)
        XCTAssertEqual(rect.size.height, 300, accuracy: 0.01)
    }

    func test_sizeOverride_bottomRightAnchor() {
        let zone = Zone(
            name: "Pinned BR",
            x: 0.5, y: 0.5, width: 0.5, height: 0.5,
            anchor: .bottomRight,
            sizeOverride: .init(width: 400, height: 300)
        )
        let rect = FrameResolver.appKitFrame(for: zone, in: visibleFrame)
        // Zone in AppKit: x:960 y:0 w:960 h:540. Pin to bottom-right of zone.
        XCTAssertEqual(rect.origin.x, 960 + 960 - 400, accuracy: 0.01)
        XCTAssertEqual(rect.origin.y, 0, accuracy: 0.01)
        XCTAssertEqual(rect.size.width, 400, accuracy: 0.01)
        XCTAssertEqual(rect.size.height, 300, accuracy: 0.01)
    }
}

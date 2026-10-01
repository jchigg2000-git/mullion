import AppKit
import XCTest
@testable import Mullion

@MainActor
final class WallpaperTintProviderTests: XCTestCase {

    func test_wallpaperChangeOnSameDisplay_recomputesTint() {
        // Regression (LIMIT-4): the tint was cached per display for the
        // app's lifetime, so changing the wallpaper (or moving to a Space
        // with a different one) kept the old, possibly clashing accent.
        let provider = WallpaperTintProvider()
        let first = URL(fileURLWithPath: "/tmp/wallpaper-a.heic")
        let second = URL(fileURLWithPath: "/tmp/wallpaper-b.heic")
        var computeCalls = 0

        let a = provider.tint(displayUUID: "D1", wallpaperURL: first) {
            computeCalls += 1; return .red
        }
        let aAgain = provider.tint(displayUUID: "D1", wallpaperURL: first) {
            computeCalls += 1; return .green
        }
        XCTAssertEqual(a, .red)
        XCTAssertEqual(aAgain, .red, "same wallpaper must hit the cache")
        XCTAssertEqual(computeCalls, 1)

        let b = provider.tint(displayUUID: "D1", wallpaperURL: second) {
            computeCalls += 1; return .blue
        }
        XCTAssertEqual(b, .blue, "new wallpaper must recompute")
        XCTAssertEqual(computeCalls, 2)
    }
}

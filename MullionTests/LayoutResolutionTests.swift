import XCTest
@testable import Mullion

/// Regression cover for the snap-hotkey defect: several layouts can match one
/// screen, and resolution used to fall out of array order. That made a newly
/// added layout inert and let a 3-zone layout answer for a 4-zone one, so
/// ⌃⌥4 hit an out-of-range index and returned silently.
@MainActor
final class LayoutResolutionTests: XCTestCase {

    private let xeneon = "4FA4DAB9-0F33-4177-98C5-14AFEF7D429B"
    private let wideAspect = 3.56

    private func layout(_ name: String,
                        _ predicate: DisplayPredicate,
                        zones: Int) -> Layout {
        Layout(
            id: UUID(),
            name: name,
            zones: (0..<zones).map {
                Zone(name: "Z\($0)",
                     x: Double($0) / Double(zones), y: 0,
                     width: 1.0 / Double(zones), height: 1,
                     anchor: .topLeft)
            },
            displayPredicate: predicate
        )
    }

    private func store(_ layouts: [Layout]) -> LayoutStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("layouts-\(UUID().uuidString).json")
        let s = LayoutStore(url: url, defaults: layouts)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return s
    }

    func test_specificDisplayBeatsAspectRatio_regardlessOfOrder() {
        let broad = layout("Any wide", .aspectRatioAtLeast(min: 2.3), zones: 3)
        let exact = layout("Xeneon 4-up", .specificDisplay(uuid: xeneon), zones: 4)

        // Declared broad-first: array order would have picked the wrong one.
        let s = store([broad, exact])
        let got = s.layout(forScreenUUID: xeneon, aspectRatio: wideAspect)
        XCTAssertEqual(got?.name, "Xeneon 4-up")
        XCTAssertEqual(got?.zones.count, 4)
    }

    func test_aspectRatioBeatsAnyDisplay() {
        let catchAll = layout("Untitled", .anyDisplay, zones: 1)
        let wide = layout("Wide", .aspectRatioAtLeast(min: 2.3), zones: 3)
        let s = store([catchAll, wide])
        XCTAssertEqual(s.layout(forScreenUUID: xeneon, aspectRatio: wideAspect)?.name, "Wide")
    }

    func test_arrangementPreferredLayoutWins_evenOverMoreSpecific() {
        let exact = layout("Xeneon 6-pane", .specificDisplay(uuid: xeneon), zones: 6)
        let wide = layout("Centre stage", .aspectRatioAtLeast(min: 2.3), zones: 3)
        let s = store([exact, wide])

        // The arrangement nominates the less specific one; the user's explicit
        // choice must still win. This is the path that was silently dropped.
        s.preferredLayoutProvider = { wide.id }
        XCTAssertEqual(s.layout(forScreenUUID: xeneon, aspectRatio: wideAspect)?.name, "Centre stage")
    }

    func test_preferredLayoutIgnoredWhenItDoesNotMatchThisScreen() {
        let other = layout("Laptop", .specificDisplay(uuid: "SOME-OTHER-UUID"), zones: 2)
        let exact = layout("Xeneon 4-up", .specificDisplay(uuid: xeneon), zones: 4)
        let s = store([other, exact])

        // Preferring a layout pinned to a different display must not blank out
        // this screen — fall through to normal ranking.
        s.preferredLayoutProvider = { other.id }
        XCTAssertEqual(s.layout(forScreenUUID: xeneon, aspectRatio: wideAspect)?.name, "Xeneon 4-up")
    }

    // MARK: Arrangement-nominated layout follows the live match

    private func arrangementStore() -> ArrangementStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("arrangements-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return ArrangementStore(url: url)
    }

    /// Regression: the nominated layout used to be pushed in on each
    /// arrangement *transition*, so it was missing at launch, ignored when the
    /// matched arrangement's default layout was edited, and kept after the
    /// displays stopped matching. It is now read from the live match.
    func test_preferredLayoutFollowsTheLiveArrangementMatch() {
        let exact = layout("Xeneon 4-up", .specificDisplay(uuid: xeneon), zones: 4)
        let wide = layout("Centre stage", .aspectRatioAtLeast(min: 2.3), zones: 3)
        let other = layout("Wide alt", .aspectRatioAtLeast(min: 2.3), zones: 2)
        let s = store([exact, wide, other])
        let arrangements = arrangementStore()
        let registry = ArrangementRegistry(arrangementStore: arrangements)
        s.followPreferredLayout(of: registry)

        // No arrangement matches: nothing is nominated, ranking decides.
        XCTAssertNil(s.preferredLayoutID)
        XCTAssertEqual(s.layout(forScreenUUID: xeneon, aspectRatio: wideAspect)?.name, "Xeneon 4-up")

        // Saving the current arrangement with a default layout applies it.
        var arrangement = registry.captureCurrent(name: "Desk", defaultLayoutID: wide.id)
        XCTAssertEqual(s.preferredLayoutID, wide.id)
        XCTAssertEqual(s.layout(forScreenUUID: xeneon, aspectRatio: wideAspect)?.name, "Centre stage")

        // Editing the matched arrangement's default layout takes effect at
        // once, with no display transition in between.
        arrangement.defaultLayoutID = other.id
        arrangements.upsert(arrangement)
        registry.recompute()
        XCTAssertEqual(s.layout(forScreenUUID: xeneon, aspectRatio: wideAspect)?.name, "Wide alt")

        // Clearing the default, or no longer matching, drops the nomination.
        arrangement.defaultLayoutID = nil
        arrangements.upsert(arrangement)
        registry.recompute()
        XCTAssertNil(s.preferredLayoutID)
        arrangement.defaultLayoutID = wide.id
        arrangements.upsert(arrangement)
        registry.recompute()
        XCTAssertEqual(s.preferredLayoutID, wide.id)
        arrangements.remove(arrangementWithID: arrangement.id)
        registry.recompute()
        XCTAssertNil(s.preferredLayoutID)
        XCTAssertEqual(s.layout(forScreenUUID: xeneon, aspectRatio: wideAspect)?.name, "Xeneon 4-up")
    }

    func test_arrangementAlreadyMatchingAtLaunch_nominatesItsLayout() {
        let wide = layout("Centre stage", .aspectRatioAtLeast(min: 2.3), zones: 3)
        let exact = layout("Xeneon 4-up", .specificDisplay(uuid: xeneon), zones: 4)
        let arrangements = arrangementStore()
        // Saved in an earlier session: the registry finds it at init, so no
        // transition ever fires `onMatched`.
        let signature = Arrangement.currentSignature(from: DisplayRegistry.shared.screens)
        arrangements.upsert(Arrangement(name: "Desk", signature: signature, defaultLayoutID: wide.id))

        let registry = ArrangementRegistry(arrangementStore: arrangements)
        let s = store([exact, wide])
        s.followPreferredLayout(of: registry)

        XCTAssertEqual(s.layout(forScreenUUID: xeneon, aspectRatio: wideAspect)?.name, "Centre stage")
    }

    func test_tieBrokenByDeclarationOrder() {
        let first = layout("First", .specificDisplay(uuid: xeneon), zones: 4)
        let second = layout("Second", .specificDisplay(uuid: xeneon), zones: 2)
        let s = store([first, second])
        XCTAssertEqual(s.layout(forScreenUUID: xeneon, aspectRatio: wideAspect)?.name, "First")
    }

    func test_noMatchReturnsNil() {
        let s = store([layout("Laptop", .specificDisplay(uuid: "OTHER"), zones: 2)])
        XCTAssertNil(s.layout(forScreenUUID: xeneon, aspectRatio: wideAspect))
    }

    func test_specificityOrdering() {
        XCTAssertGreaterThan(DisplayPredicate.specificDisplay(uuid: "x").specificity,
                             DisplayPredicate.aspectRatioAtLeast(min: 2.3).specificity)
        XCTAssertGreaterThan(DisplayPredicate.aspectRatioAtLeast(min: 2.3).specificity,
                             DisplayPredicate.anyDisplay.specificity)
    }
}

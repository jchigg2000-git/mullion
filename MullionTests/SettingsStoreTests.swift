import XCTest
@testable import Mullion

/// Exercises the drag-snap / grid modifier setters added for the Preferences
/// pane, plus the `ModifierMask.displayName` labels the pane's Pickers bind to.
/// The overlay controllers read `SettingsStore.settings` live per event, so
/// the in-memory write-through asserted here is exactly what they consume.
@MainActor
final class SettingsStoreTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mullion-settings-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func test_dragSnapModifierSetter_updatesLiveSettings() {
        let store = SettingsStore(url: tempURL)
        store.dragSnapModifier = .optionShift
        // `DragOverlayController.handleMouseDragged` reads exactly this.
        XCTAssertEqual(store.settings.dragSnapModifier, .optionShift)
        XCTAssertEqual(store.dragSnapModifier, .optionShift)
    }

    func test_gridModifierSetter_updatesLiveSettings() {
        let store = SettingsStore(url: tempURL)
        store.gridModifier = .command
        // `GridOverlayController.handleFlagsChanged` reads exactly this.
        XCTAssertEqual(store.settings.gridModifier, .command)
        XCTAssertEqual(store.gridModifier, .command)
    }

    func test_settersLeaveOtherFieldsUntouched() {
        let store = SettingsStore(url: tempURL)
        let autoBefore = store.autoRestoreEnabled
        store.dragSnapModifier = .shift
        store.gridModifier = .controlShift
        XCTAssertEqual(store.autoRestoreEnabled, autoBefore)
        XCTAssertEqual(store.dragSnapModifier, .shift)
        XCTAssertEqual(store.gridModifier, .controlShift)
    }

    /// The pre-UI workflow was hand-editing settings.json; a fresh store must
    /// still surface those values through the new getters.
    func test_reload_picksUpExternallyEditedModifiers() throws {
        let json = """
        {"version":1,"autoRestoreEnabled":true,"dragSnapModifier":"command","gridModifier":"optionShift"}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        try data.write(to: tempURL)

        let store = SettingsStore(url: tempURL)
        XCTAssertEqual(store.dragSnapModifier, .command)
        XCTAssertEqual(store.gridModifier, .optionShift)
    }

    func test_displayName_isUniqueAndNonEmpty_forEveryCase() {
        var seen = Set<String>()
        for mask in ModifierMask.allCases {
            let name = mask.displayName
            XCTAssertFalse(name.isEmpty, "\(mask) has an empty displayName")
            XCTAssertTrue(seen.insert(name).inserted, "duplicate displayName: \(name)")
        }
        // The Picker binds to `ModifierMask.allCases`; guard the count so a
        // future case addition prompts a displayName + review.
        XCTAssertEqual(ModifierMask.allCases.count, 8)
    }
}

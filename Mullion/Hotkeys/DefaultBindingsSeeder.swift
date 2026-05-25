import AppKit
import KeyboardShortcuts

/// One-time seed of default hotkeys on first launch. Mullion's data layer
/// (`bindings.json`) stores shortcut *names*, but the actual key combos live
/// in UserDefaults via the KeyboardShortcuts library. Without this seeder,
/// a fresh install boots with no hotkeys bound and nothing to test.
///
/// Idempotent — a UserDefaults flag tracks whether the seed has run.
enum DefaultBindingsSeeder {
    private static let didSeedKey = "Mullion.didSeedDefaultBindings"

    static func seedIfNeeded(bindingStore: BindingStore, layoutStore: LayoutStore) {
        guard !UserDefaults.standard.bool(forKey: didSeedKey) else { return }
        guard bindingStore.bindings.isEmpty else {
            UserDefaults.standard.set(true, forKey: didSeedKey)
            return
        }

        // Defaults map to the bundled "Standard halves and thirds" layout +
        // the "Ultrawide 6-pane" layout. Zone IDs match DefaultLayouts.json.
        let seeds: [(name: String, zoneID: String, shortcut: KeyboardShortcuts.Shortcut)] = [
            // Halves (Standard layout)
            ("mullion.leftHalf",   "a5555555-0000-0000-0000-000000000001",
             .init(.leftArrow,  modifiers: [.control, .option])),
            ("mullion.rightHalf",  "a5555555-0000-0000-0000-000000000002",
             .init(.rightArrow, modifiers: [.control, .option])),
            ("mullion.maximize",   "a5555555-0000-0000-0000-000000000006",
             .init(.upArrow,    modifiers: [.control, .option])),
            // 6-pane (ultrawide)
            ("mullion.pane.topLeft",     "a1111111-0000-0000-0000-000000000001",
             .init(.one,   modifiers: [.control, .option])),
            ("mullion.pane.topMid",      "a1111111-0000-0000-0000-000000000002",
             .init(.two,   modifiers: [.control, .option])),
            ("mullion.pane.topRight",    "a1111111-0000-0000-0000-000000000003",
             .init(.three, modifiers: [.control, .option])),
            ("mullion.pane.botLeft",     "a1111111-0000-0000-0000-000000000004",
             .init(.four,  modifiers: [.control, .option])),
            ("mullion.pane.botMid",      "a1111111-0000-0000-0000-000000000005",
             .init(.five,  modifiers: [.control, .option])),
            ("mullion.pane.botRight",    "a1111111-0000-0000-0000-000000000006",
             .init(.six,   modifiers: [.control, .option])),
        ]

        for seed in seeds {
            guard let zoneUUID = UUID(uuidString: seed.zoneID),
                  layoutStore.zone(withID: zoneUUID) != nil
            else { continue }
            let binding = HotkeyBinding(
                shortcutName: seed.name,
                targets: [zoneUUID],
                role: .snap
            )
            bindingStore.upsert(binding)
            KeyboardShortcuts.setShortcut(seed.shortcut, for: .init(seed.name))
        }

        UserDefaults.standard.set(true, forKey: didSeedKey)
    }
}

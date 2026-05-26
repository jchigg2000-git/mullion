import AppKit
import KeyboardShortcuts

/// One-time setup of the fixed ⌥⌃1..⌥⌃0 snap-by-index defaults on first
/// launch. These 10 KeyboardShortcuts.Names are managed outside
/// `bindings.json`; they map to whatever layout's displayPredicate matches
/// the focused window's screen at hotkey-press time. See
/// `HotkeyManager.indexedNames` and `ActionDispatcher.snapByIndex(_:)`.
///
/// Idempotent per seed-version flag. On upgrade from the older per-zone
/// seeded scheme (`mullion.leftHalf`, `mullion.pane.*`, etc.) this also
/// purges those obsolete entries from `bindings.json` so they don't double-
/// fire alongside the new indexed handlers.
enum DefaultBindingsSeeder {
    private static let didSeedKey = "Mullion.didSeedDefaultBindings.v2"
    private static let obsoleteShortcutNames: Set<String> = [
        "mullion.leftHalf", "mullion.rightHalf", "mullion.maximize",
        "mullion.pane.topLeft", "mullion.pane.topMid", "mullion.pane.topRight",
        "mullion.pane.botLeft", "mullion.pane.botMid", "mullion.pane.botRight",
    ]

    static func seedIfNeeded(bindingStore: BindingStore, layoutStore: LayoutStore) {
        // Always purge obsolete entries — they exist iff the user was seeded
        // under the old scheme. Cheap and safe to re-check on every launch
        // since a fresh install has none.
        purgeObsoleteBindings(bindingStore: bindingStore)

        guard !UserDefaults.standard.bool(forKey: didSeedKey) else { return }

        // Default shortcuts: ⌥⌃1..⌥⌃9 for indexes 1..9, ⌥⌃0 for index 10.
        let keys: [KeyboardShortcuts.Key] = [.one, .two, .three, .four, .five,
                                             .six, .seven, .eight, .nine, .zero]
        for (offset, key) in keys.enumerated() {
            let name = HotkeyManager.indexedNames[offset]
            KeyboardShortcuts.setShortcut(
                .init(key, modifiers: [.control, .option]),
                for: name
            )
        }

        UserDefaults.standard.set(true, forKey: didSeedKey)
    }

    private static func purgeObsoleteBindings(bindingStore: BindingStore) {
        let stale = bindingStore.bindings.filter { obsoleteShortcutNames.contains($0.shortcutName) }
        for binding in stale {
            bindingStore.remove(bindingWithID: binding.id)
        }
        // Also clear the chord-claim from UserDefaults — otherwise the old
        // Names still hold ⌃⌥1..6 (etc.) and can shadow the new indexed
        // handlers even with the binding gone.
        for shortcutName in obsoleteShortcutNames {
            KeyboardShortcuts.reset(.init(shortcutName))
        }
    }
}

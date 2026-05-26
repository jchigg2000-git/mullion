import AppKit
import KeyboardShortcuts

/// Wraps the KeyboardShortcuts library. The rest of the app talks to this
/// class via `onTrigger` (custom per-zone bindings) and `onIndexTrigger`
/// (the fixed ⌥⌃1..⌥⌃0 snap-by-index slots). LayoutEditorView also imports
/// the library directly for its Recorder UI.
final class HotkeyManager {
    /// 10 shortcut Names for the fixed ⌥⌃1..⌥⌃0 number-key convention.
    /// Index 1..9 use that digit key; index 10 maps to the physical "0".
    static let indexedNames: [KeyboardShortcuts.Name] = (1...10).map {
        KeyboardShortcuts.Name("mullion.zone.index.\($0)")
    }

    private var registered: [(id: UUID, name: KeyboardShortcuts.Name)] = []

    var onTrigger: ((UUID) -> Void)?
    var onIndexTrigger: ((Int) -> Void)?

    func register(_ bindings: [HotkeyBinding]) {
        unregisterAll()
        for binding in bindings {
            let name = KeyboardShortcuts.Name(binding.shortcutName)
            registered.append((binding.id, name))
            let id = binding.id
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                self?.onTrigger?(id)
            }
        }
        registerIndexedShortcuts()
    }

    /// Re-register the fixed ⌥⌃1..⌥⌃0 handlers. Called from `register` since
    /// `KeyboardShortcuts.removeAllHandlers()` wipes everything.
    func registerIndexedShortcuts() {
        for (offset, name) in Self.indexedNames.enumerated() {
            let index1Based = offset + 1
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                self?.onIndexTrigger?(index1Based)
            }
        }
    }

    func unregisterAll() {
        // The library only exposes a global clear. Mullion is the only client
        // of KeyboardShortcuts in this process, so clearing all handlers
        // before re-registering from the current bindings is correct.
        KeyboardShortcuts.removeAllHandlers()
        registered.removeAll()
    }
}

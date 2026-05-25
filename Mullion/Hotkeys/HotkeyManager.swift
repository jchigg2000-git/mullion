import AppKit
import KeyboardShortcuts

/// Wraps the KeyboardShortcuts library. The rest of the app talks to this
/// class via `onTrigger`; no other module imports `KeyboardShortcuts`.
final class HotkeyManager {
    private var registered: [(id: UUID, name: KeyboardShortcuts.Name)] = []

    var onTrigger: ((UUID) -> Void)?

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
    }

    func unregisterAll() {
        // The library only exposes a global clear. Mullion is the only client
        // of KeyboardShortcuts in this process, so clearing all handlers
        // before re-registering from the current bindings is correct.
        KeyboardShortcuts.removeAllHandlers()
        registered.removeAll()
    }
}

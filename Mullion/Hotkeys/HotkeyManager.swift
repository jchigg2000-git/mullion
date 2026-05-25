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
        for (_, name) in registered {
            KeyboardShortcuts.removeAllHandlers(for: name)
        }
        registered.removeAll()
    }
}

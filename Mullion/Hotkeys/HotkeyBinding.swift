import Foundation

/// Maps a keyboard shortcut to one or more zone IDs. `targets.count > 1`
/// activates cycle behavior — pressing the hotkey advances through targets
/// per (window, binding) pair.
struct HotkeyBinding: Codable, Identifiable, Hashable {
    let id: UUID
    /// The `KeyboardShortcuts.Name` raw value. Kept as a String so the data
    /// layer doesn't import the package.
    var shortcutName: String
    var targets: [UUID]
    var role: Role

    enum Role: String, Codable, Hashable {
        case snap   // move the focused window to the next target
        case focus  // focus the window currently in the next target (v1: stub)
    }

    init(id: UUID = UUID(),
         shortcutName: String,
         targets: [UUID],
         role: Role = .snap) {
        self.id = id
        self.shortcutName = shortcutName
        self.targets = targets
        self.role = role
    }
}

struct BindingCatalog: Codable {
    var version: Int
    var bindings: [HotkeyBinding]

    init(version: Int = 1, bindings: [HotkeyBinding]) {
        self.version = version
        self.bindings = bindings
    }
}

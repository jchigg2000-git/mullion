import Foundation

@MainActor
final class SettingsStore {
    private let store: JSONStore<AppSettings>

    init(url: URL = ApplicationSupport.url(for: "settings.json")) {
        self.store = JSONStore(url: url, default: .default)
    }

    var settings: AppSettings { store.value }

    var autoRestoreEnabled: Bool {
        get { store.value.autoRestoreEnabled }
        set { store.update { $0.autoRestoreEnabled = newValue } }
    }

    /// Modifier that gates drag-to-snap (#25). Written from the editor's
    /// Preferences pane; `DragOverlayController` reads `settings` live per
    /// mouse event, so a change takes effect without a restart.
    var dragSnapModifier: ModifierMask {
        get { store.value.dragSnapModifier }
        set { store.update { $0.dragSnapModifier = newValue } }
    }

    /// Modifier that reveals the grid overlay (#26). Written from the
    /// editor's Preferences pane; `GridOverlayController` reads `settings`
    /// live per flags-changed event, so a change takes effect without a
    /// restart.
    var gridModifier: ModifierMask {
        get { store.value.gridModifier }
        set { store.update { $0.gridModifier = newValue } }
    }

    func reload() { store.reload() }
}

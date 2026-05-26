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

    func reload() { store.reload() }
}

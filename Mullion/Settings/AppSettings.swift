import Foundation

struct AppSettings: Codable {
    var version: Int
    var autoRestoreEnabled: Bool

    init(version: Int = 1, autoRestoreEnabled: Bool = true) {
        self.version = version
        self.autoRestoreEnabled = autoRestoreEnabled
    }

    static let `default` = AppSettings()
}

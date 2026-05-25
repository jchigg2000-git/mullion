import AppKit
import Sparkle
import os

/// Thin wrapper over `SPUStandardUpdaterController` plus a guard against
/// the unconfigured-feed state.
///
/// On a fresh clone, `Info.plist`'s `SUFeedURL` and `SUPublicEDKey` are
/// placeholders containing `CHANGE_ME`. Sparkle would happily try to fetch
/// from `https://CHANGE_ME.invalid/...` and surface a confusing network
/// error; instead, `isConfigured` detects the placeholder and the menu
/// item is shown as "Updates not configured" with the action disabled.
///
/// See `docs/release.md` for the one-time setup that flips this on.
///
/// All methods must be called on the main thread (Sparkle requires it).
/// Not annotated `@MainActor` so it can be created in `AppDelegate`'s
/// property initializers, which run during nonisolated NSObject init.
final class UpdaterController {
    private let log = Logger(subsystem: "com.mullion.Mullion", category: "updater")
    private let controller: SPUStandardUpdaterController?
    let isConfigured: Bool

    init() {
        let configured = Self.isFeedConfigured()
        self.isConfigured = configured
        if configured {
            self.controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            self.controller = nil
            log.notice("Sparkle disabled: SUFeedURL/SUPublicEDKey not yet configured (see docs/release.md)")
        }
    }

    func checkForUpdates() {
        guard let controller else { return }
        controller.checkForUpdates(nil)
    }

    private static func isFeedConfigured() -> Bool {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        // Treat both empty strings and the sentinel placeholders as
        // "unconfigured" — generated builds before first release ship with
        // CHANGE_ME placeholders that the release pipeline rewrites.
        if feed.isEmpty || key.isEmpty { return false }
        if feed.contains("CHANGE_ME") || key.contains("CHANGE_ME") { return false }
        return true
    }
}

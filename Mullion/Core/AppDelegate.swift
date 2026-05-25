import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.mullion.Mullion", category: "lifecycle")

    private let layoutStore = LayoutStore()
    private let bindingStore = BindingStore()
    private let appRuleStore = AppRuleStore()
    private let historyStore = WindowHistoryStore()
    private let settingsStore = SettingsStore()

    private var statusItemController: StatusItemController?
    private var hotkeyManager: HotkeyManager?
    private var dispatcher: ActionDispatcher?
    private var onboardingWindow: OnboardingWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.notice("Mullion launched. Accessibility trusted: \(AccessibilityGate.shared.isTrusted, privacy: .public)")

        let menu = LayoutPickerMenu(
            layoutStore: layoutStore,
            settingsStore: settingsStore,
            onReload: { [weak self] in self?.reloadAll() },
            onToggleAutoRestore: { [weak self] enabled in
                self?.settingsStore.autoRestoreEnabled = enabled
            },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        statusItemController = StatusItemController(menuBuilder: menu)

        let dispatcher = ActionDispatcher(
            layoutStore: layoutStore,
            bindingsProvider: { [bindingStore] in bindingStore.bindings },
            history: historyStore
        )
        self.dispatcher = dispatcher

        DefaultBindingsSeeder.seedIfNeeded(bindingStore: bindingStore, layoutStore: layoutStore)

        dispatcher.onAccessibilityRequired = { [weak self] in
            self?.showOnboardingIfNeeded()
        }

        let hotkeys = HotkeyManager()
        hotkeys.onTrigger = { [weak dispatcher] id in dispatcher?.handle(bindingID: id) }
        hotkeys.register(bindingStore.bindings)
        self.hotkeyManager = hotkeys

        AccessibilityGate.shared.onTrustChange = { [weak self] trusted in
            self?.log.notice("AX trust changed: \(trusted, privacy: .public)")
            if trusted {
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            } else {
                // Rebuilds and TCC resets revoke trust mid-session. Re-surface
                // onboarding so the user gets a signal instead of silent chords.
                self?.showOnboardingIfNeeded()
            }
        }

        showOnboardingIfNeeded()

        if settingsStore.autoRestoreEnabled, AccessibilityGate.shared.isTrusted {
            AutoRestore(
                layoutStore: layoutStore,
                appRuleStore: appRuleStore,
                historyStore: historyStore,
                mover: ChainedWindowMover.default
            ).run()
        }
    }

    private func showOnboardingIfNeeded() {
        guard !AccessibilityGate.shared.isTrusted else { return }
        if let existing = onboardingWindow {
            existing.show()
            return
        }
        let win = OnboardingWindow()
        win.show()
        onboardingWindow = win
    }

    private func reloadAll() {
        layoutStore.reload()
        bindingStore.reload()
        appRuleStore.reload()
        hotkeyManager?.register(bindingStore.bindings)
        log.notice("Configuration reloaded")
    }
}

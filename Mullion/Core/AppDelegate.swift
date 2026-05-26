import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.mullion.Mullion", category: "lifecycle")

    private let layoutStore = LayoutStore()
    private let bindingStore = BindingStore()
    private let appRuleStore = AppRuleStore()
    private let historyStore = WindowHistoryStore()
    private let settingsStore = SettingsStore()
    private let focusIndex = FocusIndex()
    private let updaterController = UpdaterController()

    private var statusItemController: StatusItemController?
    private var hotkeyManager: HotkeyManager?
    private var dispatcher: ActionDispatcher?
    private var onboardingWindow: OnboardingWindow?
    private var layoutEditorWindow: LayoutEditorWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.notice("Mullion launched. Accessibility trusted: \(AccessibilityGate.shared.isTrusted, privacy: .public)")

        let menu = LayoutPickerMenu(
            layoutStore: layoutStore,
            settingsStore: settingsStore,
            updaterConfigured: updaterController.isConfigured,
            onReload: { [weak self] in self?.reloadAll() },
            onToggleAutoRestore: { [weak self] enabled in
                self?.settingsStore.autoRestoreEnabled = enabled
            },
            onOpenEditor: { [weak self] in self?.showLayoutEditor() },
            onSnapToZone: { [weak self] zoneID in self?.dispatcher?.snap(toZoneID: zoneID) },
            onCheckForUpdates: { [weak self] in self?.updaterController.checkForUpdates() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        statusItemController = StatusItemController(menuBuilder: menu)

        let dispatcher = ActionDispatcher(
            layoutStore: layoutStore,
            bindingsProvider: { [bindingStore] in bindingStore.bindings },
            history: historyStore,
            focusIndex: focusIndex
        )
        self.dispatcher = dispatcher

        DefaultBindingsSeeder.seedIfNeeded(bindingStore: bindingStore, layoutStore: layoutStore)

        dispatcher.onAccessibilityRequired = { [weak self] in
            self?.showOnboardingIfNeeded()
        }

        let hotkeys = HotkeyManager()
        hotkeys.onTrigger = { [weak dispatcher] id in dispatcher?.handle(bindingID: id) }
        hotkeys.onIndexTrigger = { [weak dispatcher] index in dispatcher?.snapByIndex(index) }
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

    private func showLayoutEditor() {
        if let existing = layoutEditorWindow {
            existing.show()
            return
        }
        let model = LayoutEditorModel(
            layoutStore: layoutStore,
            bindingStore: bindingStore,
            bindingsProvider: { [bindingStore] in bindingStore.bindings },
            onBindingsChanged: { [weak self] in
                guard let self else { return }
                self.hotkeyManager?.register(self.bindingStore.bindings)
            }
        )
        let window = LayoutEditorWindow(model: model)
        window.show()
        layoutEditorWindow = window
    }
}

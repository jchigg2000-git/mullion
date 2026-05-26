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
    private let arrangementStore = ArrangementStore()
    private let focusIndex = FocusIndex()
    private let updaterController = UpdaterController()
    private lazy var arrangementRegistry = ArrangementRegistry(arrangementStore: arrangementStore)

    private var statusItemController: StatusItemController?
    private var hotkeyManager: HotkeyManager?
    private var dispatcher: ActionDispatcher?
    private var onboardingWindow: OnboardingWindow?
    private var layoutEditorWindow: LayoutEditorWindow?
    private var configWatcher: ConfigFileWatcher?
    private weak var editorModel: LayoutEditorModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.notice("Mullion launched. Accessibility trusted: \(AccessibilityGate.shared.isTrusted, privacy: .public)")

        // Force lazy init + run a first match against the current displays
        // so `currentMatch` is populated for any subscriber that comes up
        // later in launch (status menu, editor window).
        arrangementRegistry.recompute()
        arrangementRegistry.onMatched = { [weak self] arrangement, layoutID in
            guard let self else { return }
            let layoutName = layoutID.flatMap { id in
                self.layoutStore.layouts.first { $0.id == id }?.name
            } ?? "—"
            self.log.notice("arrangement '\(arrangement.name, privacy: .public)' matched (default layout: \(layoutName, privacy: .public))")
        }
        arrangementRegistry.onUnknown = { [weak self] signature in
            self?.log.notice("unknown display arrangement (\(signature.count, privacy: .public) display(s)) — open the editor to save it")
        }

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
            focusIndex: focusIndex,
            appRuleStore: appRuleStore
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

        // FSEvents-driven auto-reload of every JSON config file. Manual
        // "Reload" stays available as a fallback.
        configWatcher = ConfigFileWatcher(directory: ApplicationSupport.directory) { [weak self] in
            self?.reloadAll()
        }

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
        historyStore.reload()
        settingsStore.reload()
        arrangementStore.reload()
        hotkeyManager?.register(bindingStore.bindings)
        // Re-run match in case arrangements.json changed on disk. The
        // editor's refreshFromStores also calls recompute(), but the editor
        // window may be closed.
        arrangementRegistry.recompute()
        editorModel?.refreshFromStores()
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
            appRuleStore: appRuleStore,
            arrangementStore: arrangementStore,
            arrangementRegistry: arrangementRegistry,
            onBindingsChanged: { [weak self] in
                guard let self else { return }
                self.hotkeyManager?.register(self.bindingStore.bindings)
            }
        )
        let window = LayoutEditorWindow(model: model)
        window.show()
        layoutEditorWindow = window
        editorModel = model
    }
}

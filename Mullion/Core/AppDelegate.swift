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
    private let workspaceStore = WorkspaceStore()
    private let focusIndex = FocusIndex()
    private let updaterController = UpdaterController()
    private let mouseEventTap = MouseEventTap()
    private lazy var arrangementRegistry = ArrangementRegistry(arrangementStore: arrangementStore)
    private lazy var workspaceController = WorkspaceController(
        layoutStore: layoutStore,
        workspaceStore: workspaceStore,
        appRuleStore: appRuleStore
    )
    private lazy var dragOverlayController = DragOverlayController(
        layoutStore: layoutStore,
        settingsStore: settingsStore,
        appRuleStore: appRuleStore,
        historyStore: historyStore
    )
    private lazy var gridOverlayController = GridOverlayController(
        layoutStore: layoutStore,
        settingsStore: settingsStore,
        appRuleStore: appRuleStore,
        historyStore: historyStore
    )

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
            self.autoRestoreBoundWorkspaces(for: arrangement)
        }
        arrangementRegistry.onUnknown = { [weak self] signature in
            self?.log.notice("unknown display arrangement (\(signature.count, privacy: .public) display(s)) — open the editor to save it")
        }

        let menu = LayoutPickerMenu(
            layoutStore: layoutStore,
            settingsStore: settingsStore,
            arrangementRegistry: arrangementRegistry,
            updaterConfigured: updaterController.isConfigured,
            onReload: { [weak self] in self?.reloadAll() },
            onToggleAutoRestore: { [weak self] enabled in
                self?.settingsStore.autoRestoreEnabled = enabled
            },
            onOpenEditor: { [weak self] in self?.showLayoutEditor() },
            onSnapToZone: { [weak self] zoneID in self?.dispatcher?.snap(toZoneID: zoneID) },
            onSaveCurrentArrangement: { [weak self] in
                guard let self else { return }
                self.showLayoutEditor()
                self.editorModel?.captureArrangement()
            },
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
                // Mount/remount the mouse tap now that we have AX trust.
                // `mount()` is idempotent.
                self?.mouseEventTap.mount()
            } else {
                // Rebuilds and TCC resets revoke trust mid-session. Re-surface
                // onboarding so the user gets a signal instead of silent chords.
                self?.showOnboardingIfNeeded()
            }
        }

        showOnboardingIfNeeded()

        // Phase E foundation (step #24): mount the shared mouse tap if we
        // already have AX trust. If not, the trust-change handler above
        // will mount it once the user grants access via onboarding.
        if AccessibilityGate.shared.isTrusted {
            mouseEventTap.mount()
        }

        // Phase E #25 + #26: drag-to-snap (⌃ alone) and hold-modifier grid
        // (⌃⌥) both subscribe to mouse events. `MouseEventTap` exposes a
        // single callback slot per event type, so we fan out here. Exact-
        // bitmask matching in `ModifierMask` ensures only one of the two
        // controllers activates for any given modifier state.
        let drag = dragOverlayController
        let grid = gridOverlayController
        mouseEventTap.onMouseDown = { [weak drag] point, flags in
            drag?.handleMouseDown(at: point, flags: flags)
        }
        mouseEventTap.onMouseDragged = { [weak drag] point, flags in
            drag?.handleMouseDragged(at: point, flags: flags)
        }
        mouseEventTap.onMouseUp = { [weak drag] point, flags in
            drag?.handleMouseUp(at: point, flags: flags)
        }
        mouseEventTap.onFlagsChanged = { [weak drag, weak grid] flags in
            drag?.handleFlagsChanged(flags)
            grid?.handleFlagsChanged(flags)
        }

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
            // The launch-time `recompute()` above ran before the onMatched
            // callback was installed, so it didn't dispatch workspace
            // auto-restore. Cover the launch case explicitly here, alongside
            // the existing AppRule/Learned auto-restore.
            if let match = arrangementRegistry.currentMatch {
                autoRestoreBoundWorkspaces(for: match)
            }
        }
    }

    /// Restore the workspace bound to `arrangement` if any. Gated by
    /// `autoRestoreEnabled` + AX trust so the callback can fire from
    /// arbitrary display-change events without surprising the user when
    /// either gate is off. When multiple workspaces are bound to the same
    /// arrangement (legal but ambiguous), the most-recently-captured one
    /// wins — `capturedAt` is the most defensible tiebreaker.
    private func autoRestoreBoundWorkspaces(for arrangement: Arrangement) {
        guard settingsStore.autoRestoreEnabled,
              AccessibilityGate.shared.isTrusted else { return }
        let bound = workspaceStore.workspaces.filter { $0.arrangementID == arrangement.id }
        guard let target = bound.max(by: { $0.capturedAt < $1.capturedAt }) else { return }
        workspaceController.restore(target)
        log.notice("auto-restored workspace '\(target.name, privacy: .public)' on arrangement match")
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
        workspaceStore.reload()
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
            workspaceStore: workspaceStore,
            workspaceController: workspaceController,
            onBindingsChanged: { [weak self] in
                guard let self else { return }
                self.hotkeyManager?.register(self.bindingStore.bindings)
            }
        )
        let window = LayoutEditorWindow(model: model)
        window.onClose = { [weak self] in
            // Drop the strong reference so the window + model deallocate,
            // releasing the model's `DisplayRegistry` observer entry.
            self?.layoutEditorWindow = nil
        }
        window.show()
        layoutEditorWindow = window
        editorModel = model
    }
}

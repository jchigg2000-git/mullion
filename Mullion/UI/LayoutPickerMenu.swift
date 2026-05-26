import AppKit

/// Builds the menu-bar dropdown. Each layout expands into a submenu of its
/// zones; clicking a zone snaps the focused window into it — the same code
/// path a hotkey would take, but reachable without a binding (e.g. for
/// user-created layouts whose zones nothing is bound to yet).
@MainActor
final class LayoutPickerMenu: NSObject {
    private let layoutStore: LayoutStore
    private let settingsStore: SettingsStore
    private let arrangementRegistry: ArrangementRegistry
    private let updaterConfigured: Bool
    private let onReload: () -> Void
    private let onToggleAutoRestore: (Bool) -> Void
    private let onOpenEditor: () -> Void
    private let onSnapToZone: (UUID) -> Void
    private let onSaveCurrentArrangement: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onQuit: () -> Void

    init(layoutStore: LayoutStore,
         settingsStore: SettingsStore,
         arrangementRegistry: ArrangementRegistry,
         updaterConfigured: Bool,
         onReload: @escaping () -> Void,
         onToggleAutoRestore: @escaping (Bool) -> Void,
         onOpenEditor: @escaping () -> Void,
         onSnapToZone: @escaping (UUID) -> Void,
         onSaveCurrentArrangement: @escaping () -> Void,
         onCheckForUpdates: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.layoutStore = layoutStore
        self.settingsStore = settingsStore
        self.arrangementRegistry = arrangementRegistry
        self.updaterConfigured = updaterConfigured
        self.onReload = onReload
        self.onToggleAutoRestore = onToggleAutoRestore
        self.onOpenEditor = onOpenEditor
        self.onSnapToZone = onSnapToZone
        self.onSaveCurrentArrangement = onSaveCurrentArrangement
        self.onCheckForUpdates = onCheckForUpdates
        self.onQuit = onQuit
    }

    func build() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        rebuild(menu)
        return menu
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        if let match = arrangementRegistry.currentMatch {
            let arrangementItem = NSMenuItem(
                title: "Arrangement: \(match.name)",
                action: nil,
                keyEquivalent: ""
            )
            arrangementItem.isEnabled = false
            menu.addItem(arrangementItem)
        } else {
            let saveItem = NSMenuItem(
                title: "Save current displays as arrangement…",
                action: #selector(saveCurrentArrangementAction),
                keyEquivalent: ""
            )
            saveItem.target = self
            menu.addItem(saveItem)
        }

        menu.addItem(.separator())

        let header = NSMenuItem(title: "Layouts", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if layoutStore.layouts.isEmpty {
            let empty = NSMenuItem(
                title: "No layouts. Edit layouts.json in Application Support.",
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for layout in layoutStore.layouts {
                let layoutItem = NSMenuItem(title: layout.name, action: nil, keyEquivalent: "")
                layoutItem.submenu = buildZoneSubmenu(for: layout)
                menu.addItem(layoutItem)
            }
        }

        menu.addItem(.separator())

        let reload = NSMenuItem(title: "Reload Layouts", action: #selector(reloadAction), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        let autoRestore = NSMenuItem(title: "Auto-restore on launch", action: #selector(toggleAutoRestoreAction), keyEquivalent: "")
        autoRestore.target = self
        autoRestore.state = settingsStore.autoRestoreEnabled ? .on : .off
        menu.addItem(autoRestore)

        let editor = NSMenuItem(title: "Layout Editor…", action: #selector(openEditorAction), keyEquivalent: "e")
        editor.target = self
        menu.addItem(editor)

        menu.addItem(.separator())

        let revealItem = NSMenuItem(title: "Reveal Config in Finder", action: #selector(revealConfig), keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)

        menu.addItem(.separator())

        if updaterConfigured {
            let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesAction), keyEquivalent: "")
            updates.target = self
            menu.addItem(updates)
        } else {
            let updates = NSMenuItem(title: "Updates not configured", action: nil, keyEquivalent: "")
            updates.isEnabled = false
            menu.addItem(updates)
        }

        let quit = NSMenuItem(title: "Quit Mullion", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func buildZoneSubmenu(for layout: Layout) -> NSMenu {
        let submenu = NSMenu(title: layout.name)
        if layout.zones.isEmpty {
            let empty = NSMenuItem(title: "No zones", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for zone in layout.zones {
                let item = NSMenuItem(
                    title: zone.name,
                    action: #selector(snapToZoneAction(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = zone.id
                submenu.addItem(item)
            }
        }
        return submenu
    }

    @objc private func snapToZoneAction(_ sender: NSMenuItem) {
        guard let zoneID = sender.representedObject as? UUID else { return }
        onSnapToZone(zoneID)
    }

    @objc private func reloadAction() {
        onReload()
    }

    @objc private func toggleAutoRestoreAction() {
        onToggleAutoRestore(!settingsStore.autoRestoreEnabled)
    }

    @objc private func openEditorAction() {
        onOpenEditor()
    }

    @objc private func saveCurrentArrangementAction() {
        onSaveCurrentArrangement()
    }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([ApplicationSupport.directory])
    }

    @objc private func checkForUpdatesAction() {
        onCheckForUpdates()
    }

    @objc private func quitAction() {
        onQuit()
    }
}

extension LayoutPickerMenu: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        rebuild(menu)
    }
}

import AppKit

/// Builds the menu-bar dropdown. In v1 the layout list is informational —
/// snapping happens via hotkey. The menu provides Reload, Auto-restore
/// toggle, and Quit.
final class LayoutPickerMenu: NSObject {
    private let layoutStore: LayoutStore
    private let settingsStore: SettingsStore
    private let onReload: () -> Void
    private let onToggleAutoRestore: (Bool) -> Void
    private let onQuit: () -> Void

    init(layoutStore: LayoutStore,
         settingsStore: SettingsStore,
         onReload: @escaping () -> Void,
         onToggleAutoRestore: @escaping (Bool) -> Void,
         onQuit: @escaping () -> Void) {
        self.layoutStore = layoutStore
        self.settingsStore = settingsStore
        self.onReload = onReload
        self.onToggleAutoRestore = onToggleAutoRestore
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
                let item = NSMenuItem(title: "  \(layout.name)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                let zonesItem = NSMenuItem(
                    title: "    \(layout.zones.count) zones",
                    action: nil,
                    keyEquivalent: ""
                )
                zonesItem.isEnabled = false
                menu.addItem(item)
                menu.addItem(zonesItem)
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

        menu.addItem(.separator())

        let revealItem = NSMenuItem(title: "Reveal Config in Finder", action: #selector(revealConfig), keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Mullion", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func reloadAction() {
        onReload()
    }

    @objc private func toggleAutoRestoreAction() {
        onToggleAutoRestore(!settingsStore.autoRestoreEnabled)
    }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([ApplicationSupport.directory])
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

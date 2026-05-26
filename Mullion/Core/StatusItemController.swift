import AppKit

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let menuBuilder: LayoutPickerMenu

    init(menuBuilder: LayoutPickerMenu) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menuBuilder = menuBuilder
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            let image = NSImage(named: "MullionMenuBarTemplate")
            image?.isTemplate = true
            button.image = image
            button.image?.accessibilityDescription = "Mullion"
            button.toolTip = "Mullion"
        }
        statusItem.menu = menuBuilder.build()
    }
}

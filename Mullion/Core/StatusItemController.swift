import AppKit

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
            let symbol = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Mullion")
            symbol?.isTemplate = true
            button.image = symbol
            button.toolTip = "Mullion"
        }
        statusItem.menu = menuBuilder.build()
    }
}

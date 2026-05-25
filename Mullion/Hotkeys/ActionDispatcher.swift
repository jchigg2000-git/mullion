import AppKit

/// Orchestrates a single hotkey trigger: resolve focused window → pick the
/// next zone in the cycle → resolve the screen → compute the frame → apply
/// via mover → record the placement.
final class ActionDispatcher {
    private let layoutStore: LayoutStore
    private let bindingsProvider: () -> [HotkeyBinding]
    private let mover: WindowMover
    private let history: WindowHistoryStore?

    private struct CycleKey: Hashable {
        let windowSignature: String
        let bindingID: UUID
    }
    private var cycleState: [CycleKey: Int] = [:]

    init(layoutStore: LayoutStore,
         bindingsProvider: @escaping () -> [HotkeyBinding],
         mover: WindowMover = ChainedWindowMover.default,
         history: WindowHistoryStore? = nil) {
        self.layoutStore = layoutStore
        self.bindingsProvider = bindingsProvider
        self.mover = mover
        self.history = history
    }

    func handle(bindingID: UUID) {
        guard let binding = bindingsProvider().first(where: { $0.id == bindingID }),
              !binding.targets.isEmpty,
              let window = FocusedWindow.current()
        else { return }

        let index = advanceCycle(for: window, bindingID: bindingID, count: binding.targets.count)
        guard binding.targets.indices.contains(index) else { return }
        let zoneID = binding.targets[index]
        guard let zone = layoutStore.zone(withID: zoneID) else { return }

        // AXWindow.axFrame is in AX (top-left global) coordinates. Convert to
        // AppKit to find the right NSScreen.
        guard let axFrame = window.axFrame,
              let appKitFrame = Geometry.axToAppKit(axFrame),
              let screen = Geometry.screen(containingAppKitRect: appKitFrame)
        else { return }

        let targetAppKit = FrameResolver.appKitFrame(for: zone, on: screen)
        guard let targetAX = Geometry.appKitToAX(targetAppKit) else { return }

        switch binding.role {
        case .snap:
            _ = mover.move(window, to: targetAX)
            if let bundleID = window.bundleIdentifier {
                history?.record(
                    bundleID: bundleID,
                    displayUUID: DisplayRegistry.uuid(for: screen),
                    zoneID: zone.id
                )
            }
        case .focus:
            // v1 stub: focus role is reserved; no-op until we have a window
            // index by zone.
            break
        }
    }

    private func advanceCycle(for window: AXWindow, bindingID: UUID, count: Int) -> Int {
        guard count > 0 else { return -1 }
        if count == 1 { return 0 }
        let signature = "\(window.pid):\(window.title ?? "")"
        let key = CycleKey(windowSignature: signature, bindingID: bindingID)
        let next: Int
        if let current = cycleState[key] {
            next = (current + 1) % count
        } else {
            next = 0
        }
        cycleState[key] = next
        return next
    }
}

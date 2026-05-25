import AppKit
import os

/// Orchestrates a single hotkey trigger: resolve focused window → pick the
/// next zone in the cycle → resolve the screen → compute the frame → apply
/// via mover → record the placement.
@MainActor
final class ActionDispatcher {
    private let log = Logger(subsystem: "com.mullion.Mullion", category: "dispatcher")
    private let layoutStore: LayoutStore
    private let bindingsProvider: () -> [HotkeyBinding]
    private let mover: WindowMover
    private let history: WindowHistoryStore?

    /// Invoked on the main thread when a chord fires but AX trust is missing.
    /// Without this, every guard in `handle` exits silently and the user sees
    /// dead keys with no signal — most often after a rebuild revokes trust.
    var onAccessibilityRequired: (@MainActor () -> Void)?

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
        log.debug("dispatch begin binding=\(bindingID, privacy: .public)")

        guard AccessibilityGate.shared.isTrusted else {
            log.notice("dispatch aborted: AX trust missing; surfacing onboarding")
            onAccessibilityRequired?()
            return
        }

        guard let binding = bindingsProvider().first(where: { $0.id == bindingID }) else {
            log.debug("dispatch aborted: no binding for id")
            return
        }
        guard !binding.targets.isEmpty else {
            log.debug("dispatch aborted: binding has no targets")
            return
        }
        guard let window = FocusedWindow.current() else {
            log.debug("dispatch aborted: no focused window")
            return
        }

        let index = advanceCycle(for: window, bindingID: bindingID, count: binding.targets.count)
        guard binding.targets.indices.contains(index) else {
            log.debug("dispatch aborted: cycle index out of range")
            return
        }
        let zoneID = binding.targets[index]
        guard let zone = layoutStore.zone(withID: zoneID) else {
            log.debug("dispatch aborted: zone not found")
            return
        }

        // AXWindow.axFrame is in AX (top-left global) coordinates. Convert to
        // AppKit to find the right NSScreen.
        guard let axFrame = window.axFrame,
              let appKitFrame = Geometry.axToAppKit(axFrame),
              let screen = Geometry.screen(containingAppKitRect: appKitFrame)
        else {
            log.debug("dispatch aborted: could not resolve window frame or screen")
            return
        }

        let targetAppKit = FrameResolver.appKitFrame(for: zone, on: screen)
        guard let targetAX = Geometry.appKitToAX(targetAppKit) else {
            log.debug("dispatch aborted: target frame conversion failed")
            return
        }

        switch binding.role {
        case .snap:
            let landed = mover.move(window, to: targetAX)
            if !landed {
                log.debug("snap did not land near target for pid=\(window.pid, privacy: .public) zone=\(zone.name, privacy: .public)")
            }
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

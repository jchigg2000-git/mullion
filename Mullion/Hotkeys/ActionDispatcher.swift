import AppKit
import os

/// Orchestrates a single hotkey trigger.
///
/// `.snap` path: focused window → next zone in cycle → screen → frame →
/// mover → history + FocusIndex writeback.
///
/// `.focus` path: next zone in cycle → FocusIndex MRU → raise. The focus
/// cycle is keyed by binding alone (not by current window) because the
/// user is rotating through zones, not through windows.
@MainActor
final class ActionDispatcher {
    private let log = Logger(subsystem: "com.mullion.Mullion", category: "dispatcher")
    private let layoutStore: LayoutStore
    private let bindingsProvider: () -> [HotkeyBinding]
    private let mover: WindowMover
    private let history: WindowHistoryStore?
    private let focusIndex: FocusIndex

    /// Invoked on the main thread when a chord fires but AX trust is missing.
    /// Without this, every guard in `handle` exits silently and the user sees
    /// dead keys with no signal — most often after a rebuild revokes trust.
    var onAccessibilityRequired: (@MainActor () -> Void)?

    private struct CycleKey: Hashable {
        let windowSignature: String
        let bindingID: UUID
    }
    private var snapCycleState: [CycleKey: Int] = [:]
    private var focusCycleState: [UUID: Int] = [:]

    init(layoutStore: LayoutStore,
         bindingsProvider: @escaping () -> [HotkeyBinding],
         mover: WindowMover = ChainedWindowMover.default,
         history: WindowHistoryStore? = nil,
         focusIndex: FocusIndex = FocusIndex()) {
        self.layoutStore = layoutStore
        self.bindingsProvider = bindingsProvider
        self.mover = mover
        self.history = history
        self.focusIndex = focusIndex
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

        switch binding.role {
        case .snap:
            handleSnap(binding: binding)
        case .focus:
            handleFocus(binding: binding)
        }
    }

    // MARK: Snap

    private func handleSnap(binding: HotkeyBinding) {
        guard let window = FocusedWindow.current() else {
            log.debug("snap aborted: no focused window")
            return
        }

        let index = advanceSnapCycle(for: window, bindingID: binding.id, count: binding.targets.count)
        guard binding.targets.indices.contains(index) else {
            log.debug("snap aborted: cycle index out of range")
            return
        }
        let zoneID = binding.targets[index]
        guard let zone = layoutStore.zone(withID: zoneID) else {
            log.debug("snap aborted: zone not found")
            return
        }

        // AXWindow.axFrame is in AX (top-left global) coordinates. Convert to
        // AppKit to find the right NSScreen.
        guard let axFrame = window.axFrame,
              let appKitFrame = Geometry.axToAppKit(axFrame),
              let screen = Geometry.screen(containingAppKitRect: appKitFrame)
        else {
            log.debug("snap aborted: could not resolve window frame or screen")
            return
        }

        let layout = layoutStore.layout(containingZoneID: zoneID)
        let targetAppKit = FrameResolver.appKitFrame(for: zone, in: layout, on: screen)
        guard let targetAX = Geometry.appKitToAX(targetAppKit) else {
            log.debug("snap aborted: target frame conversion failed")
            return
        }

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
        focusIndex.record(window: window, zoneID: zone.id)
    }

    // MARK: Focus

    private func handleFocus(binding: HotkeyBinding) {
        let index = advanceFocusCycle(bindingID: binding.id, count: binding.targets.count)
        guard binding.targets.indices.contains(index) else { return }
        let zoneID = binding.targets[index]

        guard let window = focusIndex.mostRecentAliveWindow(in: zoneID) else {
            log.debug("focus: no recorded window in zone \(zoneID, privacy: .public)")
            return
        }
        focusIndex.raise(window)
    }

    // MARK: Cycle bookkeeping

    private func advanceSnapCycle(for window: AXWindow, bindingID: UUID, count: Int) -> Int {
        guard count > 0 else { return -1 }
        if count == 1 { return 0 }
        let signature = "\(window.pid):\(window.title ?? "")"
        let key = CycleKey(windowSignature: signature, bindingID: bindingID)
        let next: Int
        if let current = snapCycleState[key] {
            next = (current + 1) % count
        } else {
            next = 0
        }
        snapCycleState[key] = next
        return next
    }

    private func advanceFocusCycle(bindingID: UUID, count: Int) -> Int {
        guard count > 0 else { return -1 }
        if count == 1 { return 0 }
        let next: Int
        if let current = focusCycleState[bindingID] {
            next = (current + 1) % count
        } else {
            next = 0
        }
        focusCycleState[bindingID] = next
        return next
    }
}

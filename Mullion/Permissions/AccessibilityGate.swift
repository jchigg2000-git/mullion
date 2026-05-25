import AppKit
import ApplicationServices
import CoreGraphics

final class AccessibilityGate {
    static let shared = AccessibilityGate()

    /// Fires on AX trust state change (System Settings toggle). Always invoked
    /// on the main queue.
    var onTrustChange: ((Bool) -> Void)?

    private init() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleAXNotification),
            name: NSNotification.Name("com.apple.accessibility.api"),
            object: nil
        )
    }

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system Accessibility prompt and returns current trust state.
    @discardableResult
    func prompt() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Live probe — `AXIsProcessTrusted` can return stale `true` after a
    /// macOS update revalidates the code signature. Creating a listen-only
    /// event tap and immediately invalidating it confirms current grant.
    func livelyTrusted() -> Bool {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else { return false }
        CFMachPortInvalidate(tap)
        return true
    }

    @objc private func handleAXNotification() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self else { return }
            self.onTrustChange?(self.isTrusted)
        }
    }
}

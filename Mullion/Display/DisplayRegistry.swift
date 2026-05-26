import AppKit
import CoreGraphics

/// Tracks connected displays with stable identity. `CGDirectDisplayID` is
/// NOT stable across reconnect, so persistence keys on the UUID from
/// `CGDisplayCreateUUIDFromDisplayID`. Falls back to a name+size signature
/// for displays without a UUID (rare on physical hardware).
///
/// Display-change notifications fan out via `observe(host:_:)` — multiple
/// subscribers (`ArrangementRegistry`, `LayoutEditorModel`, …) each register
/// against their own host object. Observer entries hold the host weakly and
/// are dropped lazily on the next fire (or eagerly on the next `observe`)
/// once the host deinits, so subscribers don't have to unregister explicitly.
@MainActor
final class DisplayRegistry {
    /// `nonisolated` so it can be referenced from nonisolated default-arg
    /// expressions (e.g. `ArrangementRegistry.init(displayRegistry:)`).
    /// Safe because the type is `Sendable` (auto-inferred for final @MainActor
    /// classes) and the `init` itself is `nonisolated`.
    nonisolated static let shared = DisplayRegistry()

    /// `nonisolated(unsafe)` so the nonisolated `init` can populate it and
    /// the nonisolated `@objc screensChanged` selector can update it inside
    /// `MainActor.assumeIsolated`. All mutation paths run on the main
    /// thread; the type system can't see that, hence the unsafe marker.
    nonisolated(unsafe) private(set) var screens: [NSScreen]
    private var debouncer: DispatchWorkItem?

    private struct Observer {
        weak var host: AnyObject?
        let callback: @MainActor () -> Void
    }
    private var observers: [Observer] = []

    /// `nonisolated` so `nonisolated(unsafe) static let shared` can evaluate
    /// this initializer at first access. `NSScreen.screens` isn't MainActor-
    /// annotated in the current AppKit headers, so reading it from a
    /// nonisolated context is permitted by the type system.
    nonisolated init() {
        self.screens = NSScreen.screens
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Register `callback` for the lifetime of `host`. The entry is retained
    /// only as long as `host` is alive; once `host` deinits, the entry is
    /// dropped on the next fire or the next `observe` call.
    func observe(host: AnyObject, _ callback: @escaping @MainActor () -> Void) {
        observers.removeAll { $0.host == nil }
        observers.append(Observer(host: host, callback: callback))
    }

    @objc private nonisolated func screensChanged() {
        // Posted on the main thread by AppKit; hop to MainActor for the
        // mutation + dispatch since the @objc selector is nonisolated.
        MainActor.assumeIsolated {
            debouncer?.cancel()
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    self.screens = NSScreen.screens
                    self.observers.removeAll { $0.host == nil }
                    for observer in self.observers where observer.host != nil {
                        observer.callback()
                    }
                }
            }
            debouncer = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
        }
    }

    nonisolated static func uuid(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let displayID = CGDirectDisplayID(number.uint32Value)
            if let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                return CFUUIDCreateString(nil, uuidRef) as String
            }
        }
        return "fallback:\(screen.localizedName):\(Int(screen.frame.width))x\(Int(screen.frame.height))"
    }

    func screen(forUUID uuid: String) -> NSScreen? {
        screens.first { Self.uuid(for: $0) == uuid }
    }
}

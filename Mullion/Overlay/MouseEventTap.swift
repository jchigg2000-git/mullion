import AppKit
import CoreGraphics
import os

/// Shared session-level `CGEventTap` for Phase E mouse-driven UX. Listens
/// (`.listenOnly`) for left-mouse down/dragged/up events; downstream
/// controllers will attach to `onMouseDown` / `onMouseDragged` / `onMouseUp`
/// — `DragOverlayController` (step #25) handles drag-to-snap, and
/// `GridOverlayController` (#26) handles hold-modifier reveal.
///
/// Step #24 (this file) is foundation: mount the tap, smoke-test that
/// events arrive on the main thread without breaking input. No UI yet.
///
/// Mouse events ride the existing AX permission — `cgSessionEventTap` +
/// `.listenOnly` doesn't require an Input Monitoring entitlement on
/// macOS 14+. If `tapCreate` returns `nil` we silently no-op until the
/// next mount attempt (the AX-trust-change handler in `AppDelegate`
/// retries).
@MainActor
final class MouseEventTap {
    private let log = Logger(subsystem: "com.mullion.Mullion", category: "mouse-tap")
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    /// Set by step #25's `DragOverlayController`. Coordinates are in
    /// Quartz global space (top-left origin). Smoke build (#24) only logs.
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?

    private static let eventMask: CGEventMask =
        (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue)
        | (1 << CGEventType.leftMouseUp.rawValue)

    /// Mount the tap on the main runloop. Returns `false` if `tapCreate`
    /// fails — most commonly because AX trust hasn't been granted yet, or
    /// macOS has temporarily disabled the tap (CPU overrun). Idempotent:
    /// any prior mount is torn down first.
    @discardableResult
    func mount() -> Bool {
        tearDown()
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: Self.eventMask,
            callback: Self.callback,
            userInfo: context
        ) else {
            log.error("CGEvent.tapCreate failed (AX trust missing or tap disabled)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        self.port = port
        self.source = source
        log.notice("mouse event tap mounted (mask=down|dragged|up)")
        return true
    }

    func tearDown() {
        if let source = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.source = nil
        }
        if let port = port {
            CGEvent.tapEnable(tap: port, enable: false)
            self.port = nil
        }
    }

    /// `@convention(c)` trampoline. Captures nothing (must not — C ABI).
    /// `userInfo` is the `MouseEventTap` instance pointer, set in `mount`.
    /// The source is attached to `CFRunLoopGetMain()`, so this fires on
    /// the main thread; `MainActor.assumeIsolated` is therefore safe.
    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<MouseEventTap>.fromOpaque(userInfo).takeUnretainedValue()
        let location = event.location
        MainActor.assumeIsolated {
            tap.handle(type: type, location: location)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handle(type: CGEventType, location: CGPoint) {
        switch type {
        case .leftMouseDown:
            // `log.notice` (default level) for step #24 smoke-test visibility.
            // Steps #25/#26 should drop to `log.debug` to keep `Console.app`
            // quiet during normal use.
            log.notice("leftMouseDown @ (\(Int(location.x), privacy: .public), \(Int(location.y), privacy: .public))")
            onMouseDown?(location)
        case .leftMouseDragged:
            onMouseDragged?(location)
        case .leftMouseUp:
            log.notice("leftMouseUp @ (\(Int(location.x), privacy: .public), \(Int(location.y), privacy: .public))")
            onMouseUp?(location)
        default:
            break
        }
    }
}

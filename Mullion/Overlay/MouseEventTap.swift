import AppKit
import CoreGraphics
import os

/// Shared session-level `CGEventTap` for Phase E mouse-driven UX. Listens
/// (`.listenOnly`) for left-mouse down/dragged/up and flags-changed events;
/// downstream controllers attach to `onMouseDown` / `onMouseDragged` /
/// `onMouseUp` / `onFlagsChanged`. `DragOverlayController` (step #25)
/// handles drag-to-snap, and `GridOverlayController` (#26) will handle
/// hold-modifier reveal.
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

    /// Coordinates are in Quartz global space (top-left origin); flags
    /// carry the current modifier state (⌥/⌃/⇧/⌘).
    var onMouseDown: ((CGPoint, CGEventFlags) -> Void)?
    var onMouseDragged: ((CGPoint, CGEventFlags) -> Void)?
    var onMouseUp: ((CGPoint, CGEventFlags) -> Void)?

    /// Fires on any modifier key change — used by overlay controllers to
    /// cancel a drag if the user releases the activation modifier mid-drag.
    var onFlagsChanged: ((CGEventFlags) -> Void)?

    private static let eventMask: CGEventMask =
        (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue)
        | (1 << CGEventType.leftMouseUp.rawValue)
        | (1 << CGEventType.flagsChanged.rawValue)

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
        log.notice("mouse event tap mounted")
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
        let flags = event.flags
        MainActor.assumeIsolated {
            tap.handle(type: type, location: location, flags: flags)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handle(type: CGEventType, location: CGPoint, flags: CGEventFlags) {
        switch type {
        case .leftMouseDown:
            log.debug("leftMouseDown @ (\(Int(location.x), privacy: .public), \(Int(location.y), privacy: .public))")
            onMouseDown?(location, flags)
        case .leftMouseDragged:
            onMouseDragged?(location, flags)
        case .leftMouseUp:
            log.debug("leftMouseUp @ (\(Int(location.x), privacy: .public), \(Int(location.y), privacy: .public))")
            onMouseUp?(location, flags)
        case .flagsChanged:
            onFlagsChanged?(flags)
        default:
            break
        }
    }
}

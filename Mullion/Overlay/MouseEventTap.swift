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
/// retries). If macOS later disables the mounted tap, it's re-enabled on
/// the spot (see `disposition(for:)`) and re-checked on display changes
/// and wake (`ensureEnabled()`). Every re-arm also re-delivers the live
/// modifier state (`resyncModifiers()`), because releases during the gap
/// were never seen.
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

    /// Where `resyncModifiers()` reads the real modifier state. Injectable
    /// so tests don't depend on what the machine's keyboard is doing.
    var currentFlags: () -> CGEventFlags = { CGEventSource.flagsState(.combinedSessionState) }

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
        switch disposition(for: type) {
        case .reenable:
            // Don't read location/flags: a tap-disabled notification isn't
            // a real input event.
            MainActor.assumeIsolated {
                tap.reenable(after: type)
            }
        case .dispatch:
            let location = event.location
            let flags = event.flags
            MainActor.assumeIsolated {
                tap.handle(type: type, location: location, flags: flags)
            }
        case .ignore:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    enum Disposition: Equatable {
        case dispatch
        case reenable
        case ignore
    }

    /// macOS disables a tap whose callback runs too long
    /// (`.tapDisabledByTimeout` — typically the main thread stalled on an
    /// AX call or a display reconfiguration) or on certain secure-input
    /// transitions (`.tapDisabledByUserInput`), and tells the tap exactly
    /// once. Missing that notice left drag-to-snap and the grid dead until
    /// relaunch, so it maps to `.reenable`.
    nonisolated static func disposition(for type: CGEventType) -> Disposition {
        switch type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged:
            return .dispatch
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return .reenable
        default:
            return .ignore
        }
    }

    private func reenable(after type: CGEventType) {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
        log.notice("mouse event tap disabled by \(reason, privacy: .public) — re-enabled")
        // We're inside the tap callback; a resync can run AX calls (the grid
        // snapshots the focused window), and a slow callback is exactly what
        // got the tap disabled. Let the callback return first.
        Task { @MainActor [weak self] in
            self?.resyncModifiers()
        }
    }

    /// While the tap was off, modifier changes were never delivered, so a
    /// release that happened in that gap leaves the grid (or a drag overlay)
    /// painted until the next click. Re-deliver the modifier state the OS
    /// reports now through the normal `onFlagsChanged` path, so the
    /// controllers see the release (or the press) they missed.
    func resyncModifiers() {
        let flags = currentFlags()
        log.notice("mouse event tap re-armed — resyncing modifier state (flags \(flags.rawValue, privacy: .public))")
        onFlagsChanged?(flags)
    }

    /// Belt-and-braces for a disable notice that never arrived: re-arm the
    /// tap if it's mounted but off. Cheap; called on display changes and
    /// on wake, the two moments a disable is most likely.
    func ensureEnabled() {
        guard let port, !CGEvent.tapIsEnabled(tap: port) else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        log.notice("mouse event tap found disabled — re-enabled")
        resyncModifiers()
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

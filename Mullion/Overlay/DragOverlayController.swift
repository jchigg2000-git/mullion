import AppKit
import CoreImage
import SwiftUI
import os

/// Drag-to-snap overlay for Phase E step #25.
///
/// State machine, driven by `MouseEventTap` callbacks:
///
///     idle ── mouseDown w/ modifier + window-at-point ──▶ tracking(window)
///     tracking ── mouseDragged ──▶ dragging(window, hover)
///     dragging ── mouseDragged ──▶ dragging(window, updated hover)
///     dragging ── mouseUp w/ hover ──▶ snap → idle
///     {tracking|dragging} ── mouseUp w/o hover ──▶ idle (no snap)
///     {tracking|dragging} ── modifier released ──▶ idle (overlay hidden)
///
/// One borderless `NSWindow` per `NSScreen` is created lazily and reused
/// across drags. Each window hosts a SwiftUI view that renders every zone
/// from that screen's matching layout — faint outlines for all zones, plus
/// fill + bold outline for the hovered one.
@MainActor
final class DragOverlayController {
    private let log = Logger(subsystem: "com.mullion.Mullion", category: "drag-overlay")
    private let layoutStore: LayoutStore
    private let settingsStore: SettingsStore
    private let appRuleStore: AppRuleStore
    private let historyStore: WindowHistoryStore
    private let mover: any WindowMover

    private enum State {
        case idle
        case dragging(window: AXWindow, hover: Hover?)
    }

    private struct Hover {
        let zone: Zone
        let layout: Layout
        let screen: NSScreen
    }

    private var state: State = .idle

    /// Window captured at the last `mouseDown`, regardless of modifier
    /// state. Held until `mouseUp` so the user can press the activation
    /// modifier *after* starting the drag and still snap whichever window
    /// they clicked. Cleared on mouseUp.
    private var candidateWindow: AXWindow?

    /// Keyed by display UUID so the cache survives a display
    /// disconnect/reconnect that keeps the same hardware identity.
    private var overlays: [String: OverlayWindow] = [:]

    /// Sampled wallpaper-complementary tint per display. Computed lazily on
    /// the first overlay show for a display; cached for the app's lifetime.
    /// Wallpaper changes mid-session don't update — re-launching picks them up.
    private let tintProvider = WallpaperTintProvider()

    init(layoutStore: LayoutStore,
         settingsStore: SettingsStore,
         appRuleStore: AppRuleStore,
         historyStore: WindowHistoryStore,
         mover: any WindowMover = ChainedWindowMover.default) {
        self.layoutStore = layoutStore
        self.settingsStore = settingsStore
        self.appRuleStore = appRuleStore
        self.historyStore = historyStore
        self.mover = mover
    }

    // MARK: - Mouse-event handlers (wired in AppDelegate)

    /// Always captures the window-at-point as a candidate, even without the
    /// modifier — `handleFlagsChanged` (or the next drag tick) can promote
    /// the candidate to active state if the user presses the modifier
    /// mid-drag.
    func handleMouseDown(at axPoint: CGPoint, flags: CGEventFlags) {
        candidateWindow = AXWindow.atScreenPoint(axPoint)
        state = .idle
    }

    func handleMouseDragged(at axPoint: CGPoint, flags: CGEventFlags) {
        guard settingsStore.settings.dragSnapModifier.isSatisfied(by: flags) else {
            cancel()
            return
        }
        guard let window = candidateWindow else { return }
        let hover = resolveHover(axPoint: axPoint)
        let firstTick: Bool
        if case .dragging = state {
            firstTick = false
        } else {
            firstTick = true
        }
        state = .dragging(window: window, hover: hover)
        if firstTick {
            showOverlays(hover: hover)
        } else {
            refreshOverlays(hover: hover)
        }
    }

    func handleMouseUp(at axPoint: CGPoint, flags: CGEventFlags) {
        let snapshot = state
        state = .idle
        candidateWindow = nil
        hideOverlays()
        if case .dragging(let window, let hover) = snapshot, let hover {
            snap(window: window, to: hover)
        } else {
            log.debug("mouseUp without hover — no snap")
        }
    }

    func handleFlagsChanged(_ flags: CGEventFlags) {
        if !settingsStore.settings.dragSnapModifier.isSatisfied(by: flags) {
            cancel()
            return
        }
        // Modifier just became satisfied. If we have a candidate but no
        // active drag, promote now so the overlay appears immediately —
        // otherwise the user wouldn't see it until they nudged the mouse.
        guard case .idle = state, let window = candidateWindow else { return }
        guard let axPoint = currentCursorAX() else { return }
        let hover = resolveHover(axPoint: axPoint)
        state = .dragging(window: window, hover: hover)
        showOverlays(hover: hover)
    }

    private func cancel() {
        if case .idle = state { return }
        state = .idle
        hideOverlays()
    }

    /// `NSEvent.mouseLocation` returns the cursor in AppKit (bottom-left,
    /// primary-screen-anchored) coords. Convert to AX so it matches the
    /// `CGEvent.location` space the rest of this controller uses.
    private func currentCursorAX() -> CGPoint? {
        Geometry.appKitToAXPoint(NSEvent.mouseLocation)
    }

    // MARK: - Hover resolution

    /// AX/Quartz cursor point → matching `(zone, layout, screen)` if the
    /// cursor lies inside a zone on the layout for that screen.
    private func resolveHover(axPoint: CGPoint) -> Hover? {
        guard let appKitPoint = Geometry.axToAppKitPoint(axPoint) else { return nil }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitPoint) }) else {
            return nil
        }
        guard let layout = layoutForScreen(screen) else { return nil }
        for zone in layout.zones {
            let zoneFrame = FrameResolver.appKitFrame(for: zone, in: layout, on: screen)
            if zoneFrame.contains(appKitPoint) {
                return Hover(zone: zone, layout: layout, screen: screen)
            }
        }
        return nil
    }

    private func layoutForScreen(_ screen: NSScreen) -> Layout? {
        let uuid = DisplayRegistry.uuid(for: screen)
        let aspect = Double(screen.frame.width / screen.frame.height)
        return layoutStore.layouts.first {
            $0.displayPredicate.matches(uuid: uuid, aspectRatio: aspect)
        }
    }

    // MARK: - Overlay lifecycle

    private func showOverlays(hover: Hover?) {
        var shown: [String] = []
        var skipped: [String] = []
        for screen in NSScreen.screens {
            let uuid = DisplayRegistry.uuid(for: screen)
            guard let layout = layoutForScreen(screen) else {
                skipped.append(screen.localizedName)
                continue
            }
            let window = overlays[uuid] ?? OverlayWindow(screen: screen)
            overlays[uuid] = window
            let highlightID = (hover?.screen == screen) ? hover?.zone.id : nil
            let tint = Color(nsColor: tintProvider.tint(for: screen))
            window.render(screen: screen, layout: layout, highlightID: highlightID, tint: tint)
            window.show()
            shown.append("\(screen.localizedName) [\(layout.name)]")
        }
        log.notice("overlay shown on: \(shown.joined(separator: ", "), privacy: .public); skipped (no matching layout): \(skipped.joined(separator: ", "), privacy: .public)")
    }

    private func refreshOverlays(hover: Hover?) {
        for (uuid, window) in overlays {
            guard let screen = NSScreen.screens.first(where: { DisplayRegistry.uuid(for: $0) == uuid }),
                  let layout = layoutForScreen(screen)
            else { continue }
            let highlightID = (hover?.screen == screen) ? hover?.zone.id : nil
            let tint = Color(nsColor: tintProvider.tint(for: screen))
            window.render(screen: screen, layout: layout, highlightID: highlightID, tint: tint)
            // Re-assert top-of-stack on every drag tick. macOS occasionally
            // reorders overlays when other apps' transient windows appear
            // (notification banners, Spotlight, the drag preview itself).
            window.show()
        }
    }

    private func hideOverlays() {
        for window in overlays.values {
            window.hide()
        }
    }

    // MARK: - Snap

    private func snap(window: AXWindow, to hover: Hover) {
        let targetAppKit = FrameResolver.appKitFrame(for: hover.zone, in: hover.layout, on: hover.screen)
        guard let targetAX = Geometry.appKitToAX(targetAppKit) else {
            log.error("AppKit→AX conversion failed")
            return
        }
        let bundleID = window.bundleIdentifier
        // Force `.aggressive` for drag-snap regardless of per-app rule:
        // macOS Sequoia's native tiling can re-snap the window ~40-100ms
        // after our write, and `.aggressive`'s verify-and-retry path is the
        // only thing that reliably wins that race. Apps that explicitly
        // need `.systemWindowManager` still fall through to `.standard`
        // in `WindowMutator`.
        let profile: CompatProfile = .aggressive
        let landed = mover.move(window, to: targetAX, profile: profile)
        if !landed {
            log.notice("drag-snap did not land near target zone=\(hover.zone.name, privacy: .public)")
        }
        if let bundleID {
            historyStore.record(
                bundleID: bundleID,
                displayUUID: DisplayRegistry.uuid(for: hover.screen),
                zoneID: hover.zone.id
            )
        }
        log.notice("drag-snap → '\(hover.zone.name, privacy: .public)' on '\(hover.screen.localizedName, privacy: .public)'")
    }
}

// MARK: - Per-display overlay window

/// Borderless, click-through `NSWindow` covering a single display. Hosts a
/// SwiftUI view that paints every zone in the layout. Held in the
/// controller's cache for the app's lifetime; cheap to leave around.
@MainActor
private final class OverlayWindow {
    private let window: NSWindow
    private let hosting: NSHostingView<OverlayContentView>

    init(screen: NSScreen) {
        let initial = OverlayContentView(zones: [], highlightID: nil, tint: .accentColor)
        let view = NSHostingView(rootView: initial)
        self.hosting = view

        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        // `.popUpMenu` (= 101) sits above macOS Sequoia's native drag preview
        // (`.floating` = 3 sat *below* it, hence the unreliable visibility).
        win.level = .popUpMenu
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        win.hasShadow = false
        win.isReleasedWhenClosed = false
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        win.contentView = view
        self.window = win
    }

    /// Render the layout's zones in screen-local, top-left-origin
    /// coordinates (matching SwiftUI's native space).
    func render(screen: NSScreen, layout: Layout, highlightID: UUID?, tint: Color) {
        var rendered: [OverlayContentView.RenderZone] = []
        rendered.reserveCapacity(layout.zones.count)
        for zone in layout.zones {
            let appKit = FrameResolver.appKitFrame(for: zone, in: layout, on: screen)
            // appKit coords are bottom-left, absolute across displays.
            // Convert to top-left, screen-local for SwiftUI.
            let localX = appKit.minX - screen.frame.minX
            let localBottomY = appKit.minY - screen.frame.minY
            let topY = screen.frame.height - (localBottomY + appKit.height)
            rendered.append(.init(
                id: zone.id,
                name: zone.name,
                frame: CGRect(x: localX, y: topY, width: appKit.width, height: appKit.height)
            ))
        }
        hosting.rootView = OverlayContentView(zones: rendered, highlightID: highlightID, tint: tint)
    }

    func show() {
        // Always `orderFront` — `.popUpMenu` sits above macOS native drag
        // previews, but a window forced behind by `orderOut` or by another
        // app's transient overlay would otherwise stay hidden. Cheap to
        // call repeatedly when already on top.
        window.orderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
    }
}

// MARK: - Wallpaper-complementary tint

/// Samples each display's desktop wallpaper once, returns a hue-rotated
/// complementary color so the overlay reads cleanly against the user's
/// background regardless of theme.
///
/// Lazy + cached: the first overlay show for a given display computes the
/// tint (CIAreaAverage to downsample to 1×1, then HSB hue + 180°); every
/// subsequent show reads the cache. Wallpaper changes during a session
/// don't refresh — restart picks them up. Cheap fallback to `.controlAccentColor`
/// if the wallpaper image can't be loaded.
@MainActor
private final class WallpaperTintProvider {
    private var cache: [String: NSColor] = [:]
    private let ciContext = CIContext()

    func tint(for screen: NSScreen) -> NSColor {
        let uuid = DisplayRegistry.uuid(for: screen)
        if let cached = cache[uuid] { return cached }
        let color = compute(for: screen) ?? .controlAccentColor
        cache[uuid] = color
        return color
    }

    private func compute(for screen: NSScreen) -> NSColor? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let ciImage = CIImage(contentsOf: url) else {
            return nil
        }
        guard let avg = averageColor(of: ciImage) else { return nil }
        return contrasting(from: avg)
    }

    /// Reduce the whole image to a 1×1 average via `CIAreaAverage` (GPU).
    private func averageColor(of image: CIImage) -> NSColor? {
        let extent = image.extent
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ]),
        let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return NSColor(
            srgbRed: CGFloat(pixel[0]) / 255.0,
            green: CGFloat(pixel[1]) / 255.0,
            blue: CGFloat(pixel[2]) / 255.0,
            alpha: 1.0
        )
    }

    /// Hue-rotate 180° (complement) and re-saturate / re-brighten so the
    /// result is always visible — averaged wallpaper colors are often
    /// desaturated/muted; the complement of a muted color is also muted
    /// unless we explicitly punch it up.
    private func contrasting(from baseColor: NSColor) -> NSColor {
        let srgb = baseColor.usingColorSpace(.sRGB) ?? baseColor
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let rotated = (h + 0.5).truncatingRemainder(dividingBy: 1.0)
        return NSColor(
            hue: rotated,
            saturation: max(s, 0.75),
            brightness: 0.85,
            alpha: 1.0
        )
    }
}

// MARK: - SwiftUI content

private struct OverlayContentView: View {
    struct RenderZone: Identifiable, Equatable {
        let id: UUID
        let name: String
        let frame: CGRect
    }

    let zones: [RenderZone]
    let highlightID: UUID?
    let tint: Color

    var body: some View {
        // `GeometryReader` fills the hosting view's bounds, giving us a
        // stable coordinate space sized to the full screen. `.position(x:y:)`
        // then places each zone's center directly in that space — `.offset`
        // on top of `.frame` was a layout-collapsing trap (ZStack reported
        // an intrinsic size near zero, so most zones fell outside the
        // hosting view's render rect).
        // Visibility tuning:
        // - Idle zones get a real fill (not clear) plus a 2pt accent-color
        //   border at 60% — readable on dark + light backgrounds, doesn't
        //   wash out window content underneath.
        // - The hovered zone gets a stronger fill, full-opacity 3pt border,
        //   and an outer shadow so the "this is where it'll snap" pop is
        //   unmistakable.
        GeometryReader { _ in
            ForEach(zones) { zone in
                let isActive = zone.id == highlightID
                let fill = isActive ? tint.opacity(0.22) : tint.opacity(0.08)
                let strokeColor = isActive ? tint : tint.opacity(0.60)
                let strokeWidth: CGFloat = isActive ? 3 : 2
                RoundedRectangle(cornerRadius: 10)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(strokeColor, lineWidth: strokeWidth)
                    )
                    .shadow(color: isActive ? tint.opacity(0.45) : .clear, radius: 12)
                    .frame(width: zone.frame.size.width, height: zone.frame.size.height)
                    .position(
                        x: zone.frame.origin.x + zone.frame.size.width / 2,
                        y: zone.frame.origin.y + zone.frame.size.height / 2
                    )
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

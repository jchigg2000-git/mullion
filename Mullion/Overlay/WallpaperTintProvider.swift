import AppKit
import CoreImage

/// Samples each display's desktop wallpaper once, returns a hue-rotated
/// complementary color so an overlay's accent reads cleanly against the
/// user's background regardless of theme.
///
/// Lazy + cached: the first request for a display computes the tint (the
/// `CIAreaAverage` filter downsamples the wallpaper to one pixel on the
/// GPU, then we rotate hue 180°); every subsequent request reads the
/// cache. Wallpaper changes during a session don't refresh — relaunching
/// picks them up. Falls back to `.controlAccentColor` if the wallpaper
/// image can't be loaded.
///
/// Used by both `DragOverlayController` (#25) and `GridOverlayController`
/// (#26) — they share one provider per controller, but the underlying
/// per-display cache lookup is what makes this safe to instantiate twice.
@MainActor
final class WallpaperTintProvider {
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

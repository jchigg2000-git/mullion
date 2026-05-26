import SwiftUI

/// Maps a zone's 0-based array index to the ⌥⌃ number-row key that snaps
/// to it (see `HotkeyManager.indexedNames` and
/// `ActionDispatcher.snapByIndex(_:)`). 0..8 → "1".."9"; 9 → "0"; 10+ has
/// no built-in key (use the per-zone Recorder).
enum ZoneIndexKey {
    static func label(for index: Int) -> String? {
        switch index {
        case 0...8: return String(index + 1)
        case 9:     return "0"
        default:    return nil
        }
    }
}

/// Renders a layout's zones inside a rectangle that matches the target
/// display's aspect ratio. Pure SwiftUI top-left coordinate space — no
/// Y-flip needed because `Zone` is already top-left (FrameResolver is the
/// only site that flips into AppKit bottom-left).
struct LivePreviewView: View {
    let layout: Layout?
    let displaySize: CGSize
    let displayName: String
    let selectedZoneID: Zone.ID?

    var body: some View {
        GeometryReader { proxy in
            let aspect = displaySize.height > 0 ? displaySize.width / displaySize.height : 16.0 / 9.0
            let available = proxy.size
            // Fit a rectangle of `aspect` inside the available space, centered.
            let fitted: CGSize = {
                let widthIfHeightLimited = available.height * aspect
                if widthIfHeightLimited <= available.width {
                    return CGSize(width: widthIfHeightLimited, height: available.height)
                } else {
                    return CGSize(width: available.width, height: available.width / aspect)
                }
            }()
            let originX = (available.width - fitted.width) / 2
            let originY = (available.height - fitted.height) / 2

            ZStack(alignment: .topLeading) {
                // Display shell
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.secondary, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor))
                    )
                    .frame(width: fitted.width, height: fitted.height)
                    .offset(x: originX, y: originY)

                if let layout {
                    ForEach(Array(layout.zones.enumerated()), id: \.element.id) { index, zone in
                        zoneView(zone: zone,
                                 index: index,
                                 surface: fitted,
                                 originX: originX,
                                 originY: originY,
                                 selected: zone.id == selectedZoneID)
                    }
                } else {
                    Text("Select a layout to preview")
                        .foregroundStyle(.secondary)
                        .frame(width: fitted.width, height: fitted.height)
                        .offset(x: originX, y: originY)
                }

                Text("\(displayName) — \(Int(displaySize.width))×\(Int(displaySize.height))  ·  \(formatAspect(aspect))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .offset(x: originX, y: originY + fitted.height + 4)
            }
        }
    }

    private func zoneView(zone: Zone,
                          index: Int,
                          surface: CGSize,
                          originX: CGFloat,
                          originY: CGFloat,
                          selected: Bool) -> some View {
        let w = max(0, CGFloat(zone.width)) * surface.width
        let h = max(0, CGFloat(zone.height)) * surface.height
        let x = originX + CGFloat(zone.x) * surface.width
        let y = originY + CGFloat(zone.y) * surface.height
        let strokeColor: Color = selected ? .accentColor : .secondary
        let fillColor: Color = selected
            ? Color.accentColor.opacity(0.18)
            : Color.secondary.opacity(0.08)
        let isDashed = zone.sizeOverride != nil

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(fillColor)
                .overlay(
                    Rectangle()
                        .strokeBorder(
                            strokeColor,
                            style: StrokeStyle(
                                lineWidth: selected ? 2 : 1,
                                dash: isDashed ? [4, 3] : []
                            )
                        )
                )

            HStack(spacing: 5) {
                if let key = ZoneIndexKey.label(for: index) {
                    Text(key)
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 14)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color.accentColor.opacity(selected ? 1.0 : 0.75))
                        )
                }
                Text(zone.name)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            .padding(4)

            if let override = zone.sizeOverride {
                anchoredOverride(zone: zone,
                                 override: override,
                                 surface: surface,
                                 strokeColor: strokeColor)
            }
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .offset(x: x, y: y)
        .allowsHitTesting(false)
    }

    /// When `sizeOverride` is set, draw a solid box inside the dashed zone
    /// bounding box showing where the fixed-size window will actually land.
    private func anchoredOverride(zone: Zone,
                                  override: Zone.PixelSize,
                                  surface: CGSize,
                                  strokeColor: Color) -> some View {
        // Approximate pixel→preview scale using the zone's preview width
        // as a stand-in (we don't have the real display visibleFrame here,
        // and the editor isn't pixel-perfect — this is a hint, not a ruler).
        let zoneW = max(1, CGFloat(zone.width)) * surface.width
        let zoneH = max(1, CGFloat(zone.height)) * surface.height
        let surfacePxW = displaySize.width
        let surfacePxH = displaySize.height
        let scaleX = zoneW / max(1, CGFloat(zone.width)) / surfacePxW
        let scaleY = zoneH / max(1, CGFloat(zone.height)) / surfacePxH
        let pxW = min(zoneW, CGFloat(override.width) * scaleX)
        let pxH = min(zoneH, CGFloat(override.height) * scaleY)

        let (ax, ay) = anchorOrigin(anchor: zone.anchor,
                                    container: CGSize(width: zoneW, height: zoneH),
                                    inner: CGSize(width: pxW, height: pxH))
        return Rectangle()
            .strokeBorder(strokeColor, lineWidth: 1)
            .frame(width: pxW, height: pxH)
            .offset(x: ax, y: ay)
    }

    private func anchorOrigin(anchor: Anchor,
                              container: CGSize,
                              inner: CGSize) -> (CGFloat, CGFloat) {
        let dx = container.width - inner.width
        let dy = container.height - inner.height
        switch anchor {
        case .topLeft:     return (0, 0)
        case .top:         return (dx / 2, 0)
        case .topRight:    return (dx, 0)
        case .left:        return (0, dy / 2)
        case .center:      return (dx / 2, dy / 2)
        case .right:       return (dx, dy / 2)
        case .bottomLeft:  return (0, dy)
        case .bottom:      return (dx / 2, dy)
        case .bottomRight: return (dx, dy)
        }
    }

    private func formatAspect(_ ratio: Double) -> String {
        // Snap to common ratios when close.
        let candidates: [(label: String, value: Double)] = [
            ("16:10", 16.0 / 10.0),
            ("16:9",  16.0 / 9.0),
            ("21:9",  21.0 / 9.0),
            ("32:9",  32.0 / 9.0),
            ("32:10", 32.0 / 10.0),
            ("4:3",   4.0 / 3.0)
        ]
        for c in candidates where abs(c.value - ratio) < 0.03 {
            return c.label
        }
        return String(format: "%.2f:1", ratio)
    }
}

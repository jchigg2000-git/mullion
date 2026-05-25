import Foundation

/// How a window is positioned within its zone when a `sizeOverride` is set.
/// Without a `sizeOverride`, the anchor is irrelevant — the window fills the zone.
enum Anchor: String, Codable, Hashable, CaseIterable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight
}

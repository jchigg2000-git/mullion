import Foundation
import CoreGraphics

/// A rectangular target region within a display.
///
/// Coordinates are normalized 0…1 within the display's `visibleFrame`, with
/// **y=0 at the top** (user-facing convention; FrameResolver flips to AppKit
/// bottom-left when computing real frames).
///
/// `sizeOverride` pins the window's pixel dimensions; the zone's rect then
/// becomes the bounding box within which the window is positioned per `anchor`.
struct Zone: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var x: Double           // 0 = left edge
    var y: Double           // 0 = top edge
    var width: Double       // 0…1
    var height: Double      // 0…1
    var anchor: Anchor
    var sizeOverride: PixelSize?

    struct PixelSize: Codable, Hashable {
        var width: Double
        var height: Double
    }

    init(id: UUID = UUID(),
         name: String,
         x: Double,
         y: Double,
         width: Double,
         height: Double,
         anchor: Anchor = .topLeft,
         sizeOverride: PixelSize? = nil) {
        self.id = id
        self.name = name
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.anchor = anchor
        self.sizeOverride = sizeOverride
    }
}

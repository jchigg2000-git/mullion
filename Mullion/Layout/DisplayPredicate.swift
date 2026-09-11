import Foundation

/// Constrains a Layout or AppRule to a subset of connected displays.
enum DisplayPredicate: Codable, Hashable {
    case anyDisplay
    case aspectRatioAtLeast(min: Double)
    case specificDisplay(uuid: String)

    /// How narrowly this predicate targets a display. Used to break ties when
    /// several layouts match the same screen: a layout pinned to this exact
    /// display should win over one that merely wants "something wide", which
    /// in turn should win over a catch-all. Without this, resolution fell back
    /// to array order and adding a layout silently did nothing.
    var specificity: Int {
        switch self {
        case .specificDisplay: return 2
        case .aspectRatioAtLeast: return 1
        case .anyDisplay: return 0
        }
    }

    func matches(uuid: String, aspectRatio: Double) -> Bool {
        switch self {
        case .anyDisplay:
            return true
        case .aspectRatioAtLeast(let min):
            return aspectRatio >= min
        case .specificDisplay(let target):
            return target == uuid
        }
    }
}

import Foundation

/// Constrains a Layout or AppRule to a subset of connected displays.
enum DisplayPredicate: Codable, Hashable {
    case anyDisplay
    case aspectRatioAtLeast(min: Double)
    case specificDisplay(uuid: String)

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

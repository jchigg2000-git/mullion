import CoreGraphics
import Foundation

/// Single-modifier activation key for overlay-driven gestures (drag-to-snap
/// in #25, grid-reveal in #26). `.none` disables the activation gate.
enum ModifierMask: String, Codable, CaseIterable {
    case none
    case shift
    case control
    case option
    case command

    /// `nil` when the mask is `.none` (no requirement). Otherwise the
    /// `CGEventFlags` bit the user must hold for the gesture to activate.
    var cgFlag: CGEventFlags? {
        switch self {
        case .none: return nil
        case .shift: return .maskShift
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .command: return .maskCommand
        }
    }

    /// `true` when the required modifier (if any) is set in `flags`. `.none`
    /// always returns `true`.
    func isSatisfied(by flags: CGEventFlags) -> Bool {
        guard let required = cgFlag else { return true }
        return flags.contains(required)
    }
}

struct AppSettings: Codable {
    var version: Int
    var autoRestoreEnabled: Bool
    var dragSnapModifier: ModifierMask

    init(version: Int = 1,
         autoRestoreEnabled: Bool = true,
         dragSnapModifier: ModifierMask = .control) {
        self.version = version
        self.autoRestoreEnabled = autoRestoreEnabled
        self.dragSnapModifier = dragSnapModifier
    }

    // Custom decoding so settings.json written before `dragSnapModifier`
    // shipped decode without migration. Default is `.control` — `.option`
    // collides with macOS Sequoia's native window-tiling activator.
    private enum CodingKeys: String, CodingKey {
        case version, autoRestoreEnabled, dragSnapModifier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decode(Int.self, forKey: .version)
        self.autoRestoreEnabled = try c.decode(Bool.self, forKey: .autoRestoreEnabled)
        self.dragSnapModifier = try c.decodeIfPresent(ModifierMask.self, forKey: .dragSnapModifier) ?? .control
    }

    static let `default` = AppSettings()
}

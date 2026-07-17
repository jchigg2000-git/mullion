import CoreGraphics
import Foundation

/// Single-modifier-or-chord activation key for overlay-driven gestures
/// (drag-to-snap in #25, grid-reveal in #26). `.none` disables the gate.
///
/// Matching is **exact-bitmask** across the four interesting modifiers
/// (shift / control / option / command). `.control` requires `⌃` held
/// *alone*; `.controlOption` requires `⌃⌥` together. This is what cleanly
/// separates the drag and grid gestures: holding both modifiers satisfies
/// only the chord, not either single-key set.
enum ModifierMask: String, Codable, CaseIterable {
    case none
    case shift
    case control
    case option
    case command
    case controlOption
    case controlShift
    case optionShift

    /// The exact set of modifier-bits required to satisfy this mask.
    /// Empty for `.none` (always satisfied).
    var requiredFlags: CGEventFlags {
        switch self {
        case .none: return []
        case .shift: return [.maskShift]
        case .control: return [.maskControl]
        case .option: return [.maskAlternate]
        case .command: return [.maskCommand]
        case .controlOption: return [.maskControl, .maskAlternate]
        case .controlShift: return [.maskControl, .maskShift]
        case .optionShift: return [.maskAlternate, .maskShift]
        }
    }

    /// `true` when the user is holding *exactly* this mask. Compares the
    /// intersection of `flags` with the four interesting modifiers (so
    /// caps-lock / fn don't accidentally disqualify a match).
    func isSatisfied(by flags: CGEventFlags) -> Bool {
        let interesting: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        let pressed = flags.intersection(interesting)
        return pressed == requiredFlags
    }

    /// Human-readable label with modifier glyphs, for Picker rows in the
    /// editor's Preferences pane. `.none` reads as "disabled" because an
    /// empty required-flag set means the gesture is always-on, which the
    /// overlay controllers treat as "no gate" — surfacing that plainly
    /// avoids the user picking it expecting a no-op.
    var displayName: String {
        switch self {
        case .none: return "None — always active"
        case .shift: return "⇧ Shift"
        case .control: return "⌃ Control"
        case .option: return "⌥ Option"
        case .command: return "⌘ Command"
        case .controlOption: return "⌃⌥ Control-Option"
        case .controlShift: return "⌃⇧ Control-Shift"
        case .optionShift: return "⌥⇧ Option-Shift"
        }
    }
}

struct AppSettings: Codable {
    var version: Int
    var autoRestoreEnabled: Bool
    var dragSnapModifier: ModifierMask
    var gridModifier: ModifierMask

    init(version: Int = 1,
         autoRestoreEnabled: Bool = true,
         dragSnapModifier: ModifierMask = .control,
         gridModifier: ModifierMask = .controlOption) {
        self.version = version
        self.autoRestoreEnabled = autoRestoreEnabled
        self.dragSnapModifier = dragSnapModifier
        self.gridModifier = gridModifier
    }

    // Custom decoding so settings.json written before the modifier fields
    // shipped decode without migration. Defaults: `.control` for drag
    // (collides with the OS less than `.option`) and `.controlOption` for
    // grid (chord, distinct from drag's single-key).
    private enum CodingKeys: String, CodingKey {
        case version, autoRestoreEnabled, dragSnapModifier, gridModifier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decode(Int.self, forKey: .version)
        self.autoRestoreEnabled = try c.decode(Bool.self, forKey: .autoRestoreEnabled)
        self.dragSnapModifier = try c.decodeIfPresent(ModifierMask.self, forKey: .dragSnapModifier) ?? .control
        self.gridModifier = try c.decodeIfPresent(ModifierMask.self, forKey: .gridModifier) ?? .controlOption
    }

    static let `default` = AppSettings()
}

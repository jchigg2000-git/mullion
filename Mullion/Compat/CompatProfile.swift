import Foundation

/// Per-app placement compatibility profile. Picks the strategy `WindowMutator`
/// uses when writing a frame to an `AXUIElement`.
///
/// `.standard` — current behavior: size → position → size with
/// `AXEnhancedUserInterface` toggled off during the write.
///
/// `.aggressive` — adds a settle delay + post-write verify-and-retry pass.
/// For Office/Electron windows that ignore the first write even with the EUI
/// dance applied.
///
/// `.systemWindowManager` — Phase G escape hatch. Defined here so AppRule's
/// data model stays complete and JSON round-trips losslessly. Treated as
/// `.standard` by the mutator until Phase G ships.
enum CompatProfile: String, Codable, Hashable, CaseIterable {
    case standard
    case aggressive
    case systemWindowManager
}

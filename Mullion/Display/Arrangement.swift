import AppKit
import Foundation

/// Stable signature for a single display within an arrangement. Point
/// dimensions and origin are rounded to a 10pt bucket to absorb scale-factor
/// noise and tiny driver-reported drift — the arrangement should match
/// across reboots even if macOS reports 3439 one boot and 3440 the next.
///
/// `displayUUID` is the identity anchor so identical-twin panels in
/// different physical positions still distinguish (per Risk #7 in design/v1.md).
struct DisplaySig: Codable, Hashable {
    let displayUUID: String
    let widthPoints: Int
    let heightPoints: Int
    let originX: Int
    let originY: Int

    init(displayUUID: String,
         widthPoints: Int,
         heightPoints: Int,
         originX: Int,
         originY: Int) {
        self.displayUUID = displayUUID
        self.widthPoints = widthPoints
        self.heightPoints = heightPoints
        self.originX = originX
        self.originY = originY
    }

    /// Rounds an arbitrary point value to the nearest 10pt bucket. Exposed
    /// so tests can build expected signatures the same way the registry does.
    static func bucket(_ value: CGFloat) -> Int {
        Int((value / 10).rounded()) * 10
    }

    static func make(from screen: NSScreen) -> DisplaySig {
        DisplaySig(
            displayUUID: DisplayRegistry.uuid(for: screen),
            widthPoints: bucket(screen.frame.width),
            heightPoints: bucket(screen.frame.height),
            originX: bucket(screen.frame.origin.x),
            originY: bucket(screen.frame.origin.y)
        )
    }
}

/// A named display arrangement. Identity is the sorted `signature` array;
/// two arrangements with the same signature are the same physical setup.
/// `defaultLayoutID`, when set, marks a layout to prefer when this
/// arrangement matches (applied by `ArrangementRegistry` consumers).
struct Arrangement: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var signature: [DisplaySig]
    var defaultLayoutID: UUID?

    init(id: UUID = UUID(),
         name: String,
         signature: [DisplaySig],
         defaultLayoutID: UUID? = nil) {
        self.id = id
        self.name = name
        self.signature = Self.canonical(signature)
        self.defaultLayoutID = defaultLayoutID
    }

    /// Sort signatures by UUID so equality is independent of the order
    /// macOS happened to return `NSScreen.screens` in. Exact-match lookups
    /// run after canonicalising both sides.
    static func canonical(_ sigs: [DisplaySig]) -> [DisplaySig] {
        sigs.sorted { $0.displayUUID < $1.displayUUID }
    }

    /// Builds the current arrangement signature from connected screens.
    static func currentSignature(from screens: [NSScreen]) -> [DisplaySig] {
        canonical(screens.map(DisplaySig.make(from:)))
    }
}

/// Persisted root for `arrangements.json`. Versioned to survive future
/// schema changes the same way `LayoutCatalog` / `AppRuleCatalog` do.
struct ArrangementCatalog: Codable {
    var version: Int
    var arrangements: [Arrangement]

    init(version: Int = 1, arrangements: [Arrangement]) {
        self.version = version
        self.arrangements = arrangements
    }
}

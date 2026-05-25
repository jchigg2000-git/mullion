import Foundation

/// One quick-set value for the X / Y / Width / Height fields in the zone
/// inspector. The label is shown in the popover; the value is what gets
/// written to the zone (normalized 0…1).
struct AxisPreset: Identifiable, Hashable {
    let label: String
    let value: Double
    var id: String { label }
}

/// Preset menus per variable. Tuned for ultrawide column layouts up to six
/// columns wide — X/Width think in columns (sixths, quarters, thirds),
/// Y/Height think in rows (no sixths, vertical real estate is shorter).
enum AxisPresets {
    static let xOrigin: [AxisPreset] = [
        .init(label: "0",   value: 0),
        .init(label: "1/6", value: 1.0 / 6),
        .init(label: "1/4", value: 0.25),
        .init(label: "1/3", value: 1.0 / 3),
        .init(label: "1/2", value: 0.5),
        .init(label: "2/3", value: 2.0 / 3),
        .init(label: "3/4", value: 0.75),
        .init(label: "5/6", value: 5.0 / 6),
    ]

    static let yOrigin: [AxisPreset] = [
        .init(label: "0",   value: 0),
        .init(label: "1/4", value: 0.25),
        .init(label: "1/3", value: 1.0 / 3),
        .init(label: "1/2", value: 0.5),
        .init(label: "2/3", value: 2.0 / 3),
        .init(label: "3/4", value: 0.75),
    ]

    static let widthSpan: [AxisPreset] = [
        .init(label: "1/6",    value: 1.0 / 6),
        .init(label: "1/4",    value: 0.25),
        .init(label: "1/3",    value: 1.0 / 3),
        .init(label: "1/2",    value: 0.5),
        .init(label: "2/3",    value: 2.0 / 3),
        .init(label: "3/4",    value: 0.75),
        .init(label: "5/6",    value: 5.0 / 6),
        .init(label: "1 full", value: 1.0),
    ]

    static let heightSpan: [AxisPreset] = [
        .init(label: "1/4",    value: 0.25),
        .init(label: "1/3",    value: 1.0 / 3),
        .init(label: "1/2",    value: 0.5),
        .init(label: "2/3",    value: 2.0 / 3),
        .init(label: "3/4",    value: 0.75),
        .init(label: "1 full", value: 1.0),
    ]
}

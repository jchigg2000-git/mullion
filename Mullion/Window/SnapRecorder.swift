import Foundation

/// What a snap leaves behind, whichever gesture produced it (hotkey, menu,
/// drag-to-snap, grid click): the learned placement for that app on that
/// display, which `AutoRestore` replays, and the per-zone focus MRU, which
/// `.focus` hotkeys raise from. Drag and grid snaps used to record only the
/// first, so a window placed by mouse could not be reached by the zone's focus
/// hotkey. One recorder keeps the gestures from drifting apart again.
@MainActor
struct SnapRecorder {
    let history: WindowHistoryStore?
    let focusIndex: FocusIndex?

    func record(window: AXWindow, bundleID: String?, screenUUID: String, zoneID: UUID) {
        if let bundleID {
            history?.record(bundleID: bundleID, displayUUID: screenUUID, zoneID: zoneID)
        }
        focusIndex?.record(window: window, zoneID: zoneID)
    }
}

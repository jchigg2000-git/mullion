import Foundation

@MainActor
final class WindowHistoryStore {
    private let store: JSONStore<LearnedPlacementCatalog>

    init(url: URL = ApplicationSupport.url(for: "window-history.json")) {
        self.store = JSONStore(url: url, default: LearnedPlacementCatalog(placements: []))
    }

    var placements: [LearnedPlacement] { store.value.placements }

    func reload() { store.reload() }

    func placement(bundleID: String, displayUUID: String) -> LearnedPlacement? {
        store.value.placements.first {
            $0.bundleID == bundleID && $0.displayUUID == displayUUID
        }
    }

    func record(bundleID: String, displayUUID: String, zoneID: UUID, at date: Date = Date()) {
        store.update { catalog in
            if let idx = catalog.placements.firstIndex(where: {
                $0.bundleID == bundleID && $0.displayUUID == displayUUID
            }) {
                catalog.placements[idx].zoneID = zoneID
                catalog.placements[idx].placedAt = date
            } else {
                catalog.placements.append(LearnedPlacement(
                    bundleID: bundleID,
                    displayUUID: displayUUID,
                    zoneID: zoneID,
                    placedAt: date
                ))
            }
        }
    }
}

import AppKit
import Observation
import os

/// Watches `DisplayRegistry` for screen-parameter changes, computes the
/// current display signature, and emits arrangement-change events. The
/// matched arrangement is published on `currentMatch`; consumers can also
/// subscribe to `onMatched` / `onUnknown` for transition callbacks.
///
/// "Apply default layout" (build-order step #23) is signalled through
/// `onMatched(arrangement, defaultLayoutID)` — `ArrangementRegistry` itself
/// does not mutate layouts. The host (`AppDelegate`, status menu) decides
/// what "apply" means in its context.
@Observable
@MainActor
final class ArrangementRegistry {
    private let log = Logger(subsystem: "com.mullion.Mullion", category: "arrangements")
    private let arrangementStore: ArrangementStore
    private let displayRegistry: DisplayRegistry

    /// The arrangement currently matching the connected displays, or `nil`
    /// when no saved arrangement matches the present signature.
    private(set) var currentMatch: Arrangement?

    /// The unsaved signature of the currently connected displays. Updated
    /// on every display-change. Drives the editor's "Save current as…"
    /// affordance — the user wants a one-click way to capture *this* setup.
    private(set) var currentSignature: [DisplaySig]

    var onMatched: ((Arrangement, UUID?) -> Void)?
    var onUnknown: (([DisplaySig]) -> Void)?

    init(arrangementStore: ArrangementStore,
         displayRegistry: DisplayRegistry = .shared) {
        self.arrangementStore = arrangementStore
        self.displayRegistry = displayRegistry
        let signature = Arrangement.currentSignature(from: displayRegistry.screens)
        self.currentSignature = signature
        self.currentMatch = arrangementStore.arrangement(matching: signature)
        // Lifetime-scoped subscription: dropped automatically when `self`
        // deinits via the weak-host check in `DisplayRegistry`.
        displayRegistry.observe(host: self) { [weak self] in
            self?.recompute()
        }
    }

    /// Force a recomputation against the current `DisplayRegistry.screens`.
    /// Called from the chained `onChange` hook and exposed for tests +
    /// store-reload callers that need to re-run matching after
    /// `arrangements.json` changed on disk.
    func recompute() {
        let signature = Arrangement.currentSignature(from: displayRegistry.screens)
        let match = arrangementStore.arrangement(matching: signature)
        currentSignature = signature
        currentMatch = match
        if let match {
            log.notice("arrangement matched: \(match.name, privacy: .public) (default layout: \(match.defaultLayoutID?.uuidString ?? "—", privacy: .public))")
            onMatched?(match, match.defaultLayoutID)
        } else {
            log.notice("no arrangement matches current signature (\(signature.count, privacy: .public) display(s))")
            onUnknown?(signature)
        }
    }

    /// Capture the current display signature as a new named arrangement and
    /// persist it. Returns the new arrangement so callers can select it in
    /// the editor.
    @discardableResult
    func captureCurrent(name: String, defaultLayoutID: UUID? = nil) -> Arrangement {
        let arrangement = Arrangement(
            name: name,
            signature: currentSignature,
            defaultLayoutID: defaultLayoutID
        )
        arrangementStore.upsert(arrangement)
        recompute()
        return arrangement
    }
}

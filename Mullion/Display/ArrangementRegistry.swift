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
    /// Fires once a newly matched arrangement has held for `settleDelay`
    /// with no further display change. Anything that moves windows on a
    /// match (workspace auto-restore) hangs off this, not `onMatched`: a
    /// dock can drop a display for a couple of seconds and bring it back,
    /// and restoring into that gap fights macOS moving the windows back.
    /// Coming back to the arrangement that held before the gap doesn't
    /// fire either: macOS puts those windows back itself.
    var onSettled: ((Arrangement) -> Void)?

    /// The 2026-10-13 LG dropout matched the laptop-only arrangement for
    /// 2.65 s before the display returned.
    static let defaultSettleDelay: TimeInterval = 4
    private let settleDelay: TimeInterval
    @ObservationIgnored private var settleWork: DispatchWorkItem?
    /// The match that last held for `settleDelay` (`nil`: no match held).
    /// Launch counts as settled; the host restores that match itself.
    @ObservationIgnored private var settledID: UUID?

    init(arrangementStore: ArrangementStore,
         displayRegistry: DisplayRegistry = .shared,
         settleDelay: TimeInterval = ArrangementRegistry.defaultSettleDelay) {
        self.arrangementStore = arrangementStore
        self.displayRegistry = displayRegistry
        self.settleDelay = settleDelay
        let signature = Arrangement.currentSignature(from: displayRegistry.screens)
        self.currentSignature = signature
        let match = arrangementStore.arrangement(matching: signature)
        self.currentMatch = match
        self.settledID = match?.id
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
        let previousMatch = currentMatch
        let previousMatchID = previousMatch?.id
        currentSignature = signature
        currentMatch = match
        // Gate `onMatched` / `onUnknown` on actual *transitions*. Without
        // this guard, any FSEvents-driven reloadAll (a grid-snap writing
        // window-history.json, a settings change, etc.) would re-fire
        // onMatched and yank windows back into a bound workspace every time
        // the user moved something themselves — the loop you hit during the
        // 2026-05-26 bug hunt.
        if let match {
            if match.id != previousMatchID {
                log.notice("arrangement matched: \(match.name, privacy: .public) (default layout: \(match.defaultLayoutID?.uuidString ?? "—", privacy: .public))")
                onMatched?(match, match.defaultLayoutID)
            }
        } else if previousMatchID != nil {
            log.notice("no arrangement matches current signature (\(signature.count, privacy: .public) display(s))")
            onUnknown?(signature)
        }
        updateSettle(from: previousMatch, to: match)
    }

    /// Any change of match (including to no match) starts the settle
    /// clock; any recompute while it runs restarts it (the displays are
    /// still moving). The clock only ever times `currentMatch`, which
    /// changes nowhere but here.
    private func updateSettle(from previous: Arrangement?, to match: Arrangement?) {
        let wasSettling = settleWork != nil
        settleWork?.cancel()
        settleWork = nil
        if wasSettling, let previous, previous.id != match?.id {
            log.notice("arrangement '\(previous.name, privacy: .public)' did not settle — auto-restore skipped")
        }
        guard wasSettling || match?.id != previous?.id else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.settle() }
        }
        settleWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: item)
    }

    private func settle() {
        settleWork = nil
        let match = currentMatch
        guard match?.id != settledID else {
            if let match {
                log.notice("arrangement '\(match.name, privacy: .public)' came back before anything else settled — auto-restore skipped")
            }
            return
        }
        settledID = match?.id
        guard let match else { return }
        log.notice("arrangement settled: \(match.name, privacy: .public)")
        onSettled?(match)
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

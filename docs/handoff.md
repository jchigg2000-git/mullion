# Handoff — 2026-05-25 22:02 local

## What shipped (this session)
- **Phase D — arrangement detection + arrangement → default layout** (build-order steps #22, #23 in `docs/design/v1.md`).
  - New: `Mullion/Display/Arrangement.swift` (`DisplaySig`, `Arrangement`, `ArrangementCatalog` + 10pt-bucket signature canonicalization).
  - New: `Mullion/Display/ArrangementStore.swift` (`JSONStore<ArrangementCatalog>` at `~/Library/Application Support/Mullion/arrangements.json`, exact-match `arrangement(matching:)` lookup that canonicalises both sides).
  - New: `Mullion/Display/ArrangementRegistry.swift` (`@Observable @MainActor`; chains `DisplayRegistry.onChange`; emits `onMatched(arrangement, defaultLayoutID)` / `onUnknown(signature)`; exposes `captureCurrent(name:)`).
  - New: `Mullion/UI/ArrangementsEditorView.swift` (edit-immediate "Saves automatically" form; name + default-layout picker + read-only signature table + "Recapture from current" affordance; "(matched)" badge on currently-matching arrangement).
  - Editor: `LayoutEditorModel` + `LayoutEditorView` get an "Arrangements" sidebar section, `.arrangement(UUID)` `EditorSelection` case, and a "Save current displays as arrangement" entry in the `+` menu.
  - AppDelegate: instantiates `ArrangementStore` + lazy `ArrangementRegistry`, wires `onMatched` / `onUnknown` logging, includes the store in `reloadAll()`, calls `recompute()` on reload + on editor open.
  - Tests: `MullionTests/ArrangementTests.swift` — 9 tests (bucket rounding, canonical-sort equality, store CRUD/match, order-independent match, catalog JSON roundtrip with + without `defaultLayoutID`).
- Test count: **52 → 61, all passing.**
- Project: `xcodegen generate` was required to pull the new files into the locally-generated `Mullion.xcodeproj/project.pbxproj` (gitignored per prior handoff — confirmed via `git check-ignore`). `xcodebuild` reads the local .pbxproj, so any new `Mullion/` file needs `xcodegen generate` before `xcodebuild` will compile it; fresh clones regenerate on first build.

## In-flight
None — working tree has only the modified handoff + new Phase D files. No stashes, no `ship/` branches.

## Decisions (this session)
- "Apply default layout" (step #23) is signalled via `ArrangementRegistry.onMatched`; the registry does NOT mutate layouts itself. AppDelegate today only logs the match — wiring a behavioural side effect (auto-snap, status-menu indicator, AutoRestore using the matched layout) is deliberately deferred until the StatusItem / `LayoutPickerMenu` grows a "current arrangement" surface.
- Signature is rounded to a 10pt bucket via `DisplaySig.bucket(_:)` to absorb scale/driver noise. `displayUUID` is in the signature so identical-twin panels still distinguish (per Risk #7 in `docs/design/v1.md`).
- Signature canonicalization: `Arrangement.canonical(_:)` sorts by UUID, so equality is independent of `NSScreen.screens` order. `ArrangementStore.arrangement(matching:)` canonicalises both sides before comparing.
- Default-layout Picker uses a static all-zeros UUID sentinel for "None" because SwiftUI `Picker` can't carry `nil` through a `Binding<UUID>`. Hoisted to `private static let` to avoid per-render allocation.
- The Arrangements sidebar item has no order semantics (unlike Layouts where order = snap-by-index match order), so ↑↓ stays inert for it — matches Bindings/Rules behaviour.

## Don't break
- `EditorSelection.arrangement(UUID)` must use a non-Optional tag in the `List(selection:)` like the other cases (`Mullion/UI/LayoutEditorView.swift:158-180`) — wrapping in `Optional(...)` re-introduces the tap-routing breakage called out in the prior handoff.
- `ArrangementRegistry` and `LayoutEditorModel` both chain `DisplayRegistry.shared.onChange` using the save-and-restore-on-deinit pattern. Safe today because: `AR` is created lazily at launch and never released; `EM` is created on first editor open and never nilled (per deferred reviewer item #7). Order is `EM.deinit < AR.deinit`. If/when a third subscriber appears, or `EM` gains a true close lifecycle, refactor `DisplayRegistry.onChange` to a multicast token list before chaining (note in `ArrangementRegistry.swift:14-25`).
- After adding files in `Mullion/`, run `xcodegen generate` before `xcodebuild`. Forgetting this manifests as `Cannot find 'Foo' in scope` errors at compile time even when the file exists on disk.

## Next session: start here
Phase D is shipped. Per `docs/design/v1.md` build order, **Phase E — mouse-driven UX** is next (steps #24, #25, #26): mount the shared `CGEventTap`, then drag-to-snap overlay, then hold-modifier-grid overlay. This is the heaviest UI chunk in v1 and the foundation for the discoverability story (a user without hotkey muscle memory needs the overlay).

Alternative chunks worth considering before Phase E:
1. **Status-menu integration of `currentMatch`** — surface "Arrangement: Home desk" in the menu-bar dropdown; offer a "Save current as…" affordance when `currentMatch == nil`. Maybe 20 minutes; closes the user-facing loop on Phase D rather than relying on log lines.
2. **Wire AppDelegate `onMatched` to a real side effect** — e.g. when a match has `defaultLayoutID`, move that layout to position 0 in the layout list (snap-by-index then resolves to it first). Touches `LayoutStore` and has UX implications worth thinking about before just doing.
3. **The Swift-6 hygiene pass** (see Deferred) — three reviewer items, now plus `ArrangementStore` itself which is currently un-annotated. Bundle as one PR before Phase E.

## Deferred / open
- swift-reviewer #5: `JSONStore` + all store classes (incl. new `ArrangementStore`) lack `@MainActor` annotation; safe today (every caller is main-isolated) but Swift 6 strict-concurrency will warn. Bundle with the items below.
- swift-reviewer Phase-C-pass #1: `Mullion/Window/WindowMutator.swift:53` `DispatchQueue.main.asyncAfter` captures `AXUIElement` (non-Sendable) across isolation.
- swift-reviewer #7: `Mullion/Core/AppDelegate.swift:118` (now shifted) `layoutEditorWindow` is never nilled after close. Note: the Phase D chain-and-restore-deinit invariant in `ArrangementRegistry` partially DEPENDS on this not being fixed; fix together with a multicast `DisplayRegistry.onChange` refactor.
- Phase D follow-up: the actual behavioural application of `defaultLayoutID` (status-menu indicator, auto-snap on match, etc.) is unscoped. Today it's a log line only. See "Next session" alternative #1 / #2.

## How to verify
```
git log --oneline -3
git status
xcodegen generate
xcodebuild -project Mullion.xcodeproj -scheme Mullion -destination 'platform=macOS' test 2>&1 | grep "Executed.*tests" | tail -1
```

Expected: HEAD at `b00ae8e` (nothing committed this session), working tree shows the modified handoff + new `Mullion/Display/Arrangement*.swift` + new `Mullion/UI/ArrangementsEditorView.swift` + modified `LayoutEditorModel.swift`/`LayoutEditorView.swift`/`AppDelegate.swift` + new `MullionTests/ArrangementTests.swift` + regenerated `Mullion.xcodeproj/project.pbxproj`, `Executed 61 tests, with 0 failures`.

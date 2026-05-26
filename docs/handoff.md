# Handoff — 2026-05-25 22:18 local

## What shipped (this session)
- `420f27a` — feat: arrangement detection + arrangement->default layout (Phase D). Closes build-order steps #22, #23 in `docs/design/v1.md`. Touches `Mullion/Display/` (3 new files), `Mullion/UI/` (1 new + 2 modified), `Mullion/Core/AppDelegate.swift`, `MullionTests/ArrangementTests.swift`, `docs/handoff.md`. 740 insertions / 2 deletions. Tests: 52 → 61, all pass. Shipped via `/shipit` — ship branch FF-merged, local + remote ship branch deleted, `origin/main` at `420f27a`.

## In-flight
None. Working tree clean on `main`, in sync with `origin/main`, no stashes, no leftover `ship/` branches.

A debug build at `build/dd/Build/Products/Debug/Mullion.app` (gitignored) was launched mid-session to verify the editor visually — same code as `420f27a`. If you want the Mullion process running in the menu bar to track future builds cleanly, kill it (`pkill -x Mullion`) and relaunch from a fresh build.

## Decisions (this session)
- **"Apply default layout" (step #23) is signalled via callbacks, not direct mutation.** `ArrangementRegistry.onMatched(arrangement, defaultLayoutID)` fires; AppDelegate today only logs the match. The status menu / AutoRestore / a "Set as current" gesture remain unwritten — Phase D wires the data flow but does not commit to a UX surface for "applying" yet.
- **`DisplaySig` rounds to 10pt buckets and includes `displayUUID`** to absorb scale-factor noise and distinguish identical-twin panels per Risk #7 in `docs/design/v1.md`. Test `test_bucket_rounds_to_nearest_10pt` in `MullionTests/ArrangementTests.swift:21-30` is the canonical reference for the rounding rule.
- **Default-layout Picker uses a static all-zeros UUID sentinel** for "None" because SwiftUI `Picker` can't carry `nil` through `Binding<UUID>`. Hoisted to `ArrangementsEditorView.noneLayoutSentinel` (static let, no force unwrap).
- No new auto-memory entries this session. Existing memory still applicable: [[mullion-editor-ui-conventions]] (used to build the Arrangements sidebar section), [[mullion-release-pipeline]], [[feedback-stop-renagging]].

## Don't break
- **`EditorSelection.arrangement(UUID)` must use a non-Optional tag** in `List(selection:)` like the other cases (`Mullion/UI/LayoutEditorView.swift:181-200`). Wrapping in `Optional(...)` breaks tap-routing after sidebar mutations under `@Observable` — same trap called out for the other editor sections.
- **`ArrangementRegistry` and `LayoutEditorModel` both chain `DisplayRegistry.shared.onChange`** with the save-and-restore-on-deinit pattern (`Mullion/Display/ArrangementRegistry.swift:25-37`, `Mullion/UI/LayoutEditorModel.swift:78-89`). Safe today because `AR` outlives `EM`. If a third subscriber appears, or `EM` ever gets nilled on close (currently kept alive by deferred reviewer item #7), refactor `DisplayRegistry.onChange` to a multicast token list **before** adding the third chain.
- **After adding files in `Mullion/`, run `xcodegen generate` before `xcodebuild`.** `Mullion.xcodeproj/project.pbxproj` is gitignored (`git check-ignore` confirmed); the .pbxproj on disk is locally generated from `project.yml`. Skipping `xcodegen generate` produces phantom "Cannot find 'X' in scope" errors at compile time even when the file exists.

## Next session: start here
Per `docs/design/v1.md` build order, **Phase E — mouse-driven UX** (steps #24, #25, #26) is the next chunk: mount the shared `CGEventTap`, then drag-to-snap overlay, then hold-modifier grid overlay. This is the heaviest UI work in v1 and unlocks the discoverability story for users without hotkey muscle memory.

Concrete first steps for Phase E:
- Read `docs/design/v1.md` "Drag/grid overlay tap" (~lines 254-261) and step #24 (~line 377).
- Create `Mullion/Overlay/MouseEventTap.swift` (listed in module breakdown, missing from disk). Smoke test: log left-mouse events without breaking input.
- Then `Mullion/Overlay/DragOverlayController.swift` — borderless `NSWindow`-per-display, highlight on hover, snap on release.

Worth considering before Phase E:
- **Close the user-facing loop on Phase D.** Today `onMatched` only logs. A 20-minute follow-up: surface "Arrangement: <name>" in the menu-bar dropdown via `LayoutPickerMenu`; offer "Save current as…" when `currentMatch == nil`. See `Mullion/UI/LayoutPickerMenu.swift:38-104` for the menu shape.
- **Swift 6 hygiene pass.** Four reviewer items now bundle cleanly: `JSONStore` + `AppRuleStore` + `LayoutStore` + (new) `ArrangementStore` lack `@MainActor`; `WindowMutator.swift:53` captures non-Sendable `AXUIElement` across isolation; `AppDelegate.swift` `layoutEditorWindow` never nilled. Doing this **before** Phase E keeps the new mouse code Swift-6-clean from day one.

## Deferred / open
- swift-reviewer #5: `JSONStore` + all four store classes lack `@MainActor`. Safe today (every caller is main-isolated). Swift 6 strict-concurrency will warn.
- swift-reviewer Phase-C-pass #1: `Mullion/Window/WindowMutator.swift:53` `DispatchQueue.main.asyncAfter` captures `AXUIElement` (non-Sendable) across isolation.
- swift-reviewer #7: `Mullion/Core/AppDelegate.swift` `layoutEditorWindow` is never nilled after close. **Coupled with the chain-and-restore invariant in `ArrangementRegistry`** — fix together with a multicast `DisplayRegistry.onChange` refactor.
- Phase D follow-up: the behavioural application of `defaultLayoutID` (status-menu indicator, auto-snap on match, AutoRestore integration) is unscoped. Today it's a log line only.
- `Mullion/Hotkeys/HotkeyBinding.swift:16` `case focus` marked "v1: stub" — intentional, deferred per design.
- `Mullion/UI/AppRulesEditorView.swift:234` Phase G escape hatch — intentional, deferred per design.
- `Mullion/Update/UpdaterController.swift:35` Sparkle disabled until `SUFeedURL`/`SUPublicEDKey` are configured. Holding for v1.0 first public release per [[mullion-release-pipeline]].

## How to verify
```
git log --oneline -3
git status
xcodegen generate
xcodebuild -project Mullion.xcodeproj -scheme Mullion -destination 'platform=macOS' test 2>&1 | grep "Executed.*tests" | tail -1
```

Expected: HEAD at `420f27a`, clean working tree in sync with `origin/main`, `Executed 61 tests, with 0 failures`.

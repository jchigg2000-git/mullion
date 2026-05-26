# Handoff — 2026-05-26 10:35 local

## What shipped (this session)
- `7ef78e9` — feat: Phase E foundation + Swift 6 hygiene pass. Three swift-reviewer items cleared (`@MainActor` on every store + `JSONStore`; `WindowMutator.swift:53` `AXUIElement` Sendable capture replaced with `Task { @MainActor … }`; `DisplayRegistry.onChange` rewritten as a weak-host multicast and `LayoutEditorModel` now actually deinits via `LayoutEditorWindow.onClose`). Phase E step #24: new `Mullion/Overlay/MouseEventTap.swift` mounts a session-level `CGEventTap(.listenOnly)` for left-mouse-down/dragged/up + flags-changed, callback on main runloop via `MainActor.assumeIsolated`. (Note: this commit was bundled by another agent and also touched `docs/release.md` + `scripts/release.sh` — repo-path + Developer-ID identity fix, not Phase E.)
- `5efbe76` — feat: Phase E #25 drag-to-snap overlay with wallpaper-tinted zones. New `Mullion/Overlay/DragOverlayController.swift` + per-display SwiftUI overlay; press ⌃ before *or* during the left-drag → all zones outline, hovered zone fills + glows. Release in a zone snaps via `.aggressive` `WindowMutator` profile (only profile that wins the macOS Sequoia native-tiling race). Wallpaper sampled per display via `CIAreaAverage`, hue-rotated 180° for a contrasting tint. 6 files touched, 587/-24 lines. Tests: 61, all pass.

## In-flight
**Phase E #26 (grid overlay) is uncommitted in the working tree.** Files:
- `Mullion/Overlay/WallpaperTintProvider.swift` (new) — lifted out of `DragOverlayController.swift` to internal access so `GridOverlayController` can reuse it.
- `Mullion/Overlay/GridOverlayController.swift` (new) — hold-modifier grid reveal; per-display non-activating `NSPanel` paints zones + big 1-9/0 badges in their centres; click a zone snaps the captured-at-reveal focused window via the same `.aggressive` profile.
- `Mullion/Overlay/DragOverlayController.swift` (modified) — removed the in-file `WallpaperTintProvider` (now imported from the lifted file).
- `Mullion/Settings/AppSettings.swift` (modified) — `ModifierMask` refactored to **exact-bitmask** matching across `{shift, control, option, command}` (so holding ⌃⌥ no longer satisfies `.control`); added `.controlOption / .controlShift / .optionShift` cases; new `gridModifier: ModifierMask` field (default `.controlOption`).
- `Mullion/Core/AppDelegate.swift` (modified) — lazy `GridOverlayController`; `onFlagsChanged` now fans out to both controllers.

Smoke-tested in the running app (PID `27851`): grid reveals on all three displays with badges visible, click-snap lands, focus stays on the source app (non-activating panel), keyboard `⌥⌃<n>` still snaps via the existing hotkey path. Drag-snap unchanged.

A debug build at `~/Library/Developer/Xcode/DerivedData/Mullion-bpvwblqjcwcevmhhbmmwsxlwmnts/Build/Products/Debug/Mullion.app` is running — kill via `pkill -x Mullion` before relaunching from a future build.

## Decisions (this session)
- **`dragSnapModifier` default switched from `.option` to `.control`.** `.option`-drag is macOS Sequoia's native window-tiling activator and was racing our snap; `.control` doesn't collide with any OS gesture.
- **`gridModifier` is the `.controlOption` chord, not a single key.** A chord is the only way to cleanly distinguish from drag-snap's `.control` without depending on whether the mouse button is held.
- **`ModifierMask.isSatisfied` now does exact-bitmask matching** across the four interesting modifiers (shift/control/option/command). Required for the chord-vs-single-key disambiguation above — `.control` won't accidentally match while ⌥ is also pressed.
- **Drag-snap and grid-snap both force `CompatProfile.aggressive`** regardless of per-app rule. The verify-and-retry path is what wins the race against macOS Sequoia's native tiling fighting back ~40-100ms after our write. Apps that explicitly need `.systemWindowManager` still fall through to `.standard` in `WindowMutator`.
- **Overlay windows live at `.popUpMenu` level (101).** `.floating` (3) sat *below* the OS drag preview — the user reported the overlay was invisible until we raised the level. `show()` was also made to always `orderFront` so transient OS overlays (notification banners, Spotlight) can't bury us.
- **Grid panels use `.nonactivatingPanel` style** so clicking a zone doesn't steal focus from the user's actual window. Focused window is snapshotted at the moment of modifier-press, used for snap on click.
- **Drag overlay layout bug worth remembering:** the SwiftUI `.frame(w,h).offset(x,y)` combination collapses the ZStack's intrinsic size to ~zero and most zones fell outside the hosting view's render rect (user saw "half of one zone"). The fix is `GeometryReader` + `.position(x:y:)` for direct absolute placement. Same pattern reused in `GridContentView`.
- No new auto-memory entries this session — every decision above is captured in the code's own comments.

## Don't break
- **`ModifierMask` is exact-bitmask now**, not bitwise-contains. Adding a new gesture means picking a non-overlapping mask, or accepting that two gestures fire on the same modifier state (and disambiguating in the controller).
- **`WallpaperTintProvider` lives at internal scope** in `Mullion/Overlay/WallpaperTintProvider.swift`. Each overlay controller owns its own instance — the underlying cache is per-instance, so two instances each pay one wallpaper-sample cost per display. Cheap enough to not bother sharing.
- **`MouseEventTap` exposes one callback slot per event type.** Fan-out happens in `AppDelegate`. If a third overlay controller appears, update the closures in `AppDelegate.applicationDidFinishLaunching` rather than introducing a multicast inside `MouseEventTap`.
- **`GridOverlayPanel` accepts clicks** (`ignoresMouseEvents = false`); `DragOverlayWindow` is click-through (`ignoresMouseEvents = true`). Do not unify the two without revisiting the click-routing path.
- **After adding files in `Mullion/`, run `xcodegen generate` before `xcodebuild`.** Same as last session — `Mullion.xcodeproj/project.pbxproj` is gitignored, locally generated from `project.yml`.

## Next session: start here

**Phase E is complete.** Build order (`docs/design/v1.md`) puts **Phase F — workspaces** next:

- **Step #27 — Workspaces: capture + restore.** UI in the editor window. A workspace = snapshot of (windowID, bundleID, zoneID) tuples at capture time. Restore reapplies the placements. No arrangement binding yet.
- **Step #28 — Workspaces: arrangement binding.** Auto-restore a workspace when its bound arrangement matches the current display signature. Builds on `ArrangementRegistry.onMatched` (the callback `AppDelegate` currently only logs — Phase D wired the data flow but left the application open).

Concrete first steps for #27:
1. Read `docs/design/v1.md` "Workspaces" section + step #27 line.
2. Define `Workspace` + `WorkspaceCatalog` Codable types alongside `Arrangement` / `AppRule` / etc. Add a `WorkspaceStore` wrapping `JSONStore<WorkspaceCatalog>`.
3. Editor sidebar gets a new section (follow the `[[mullion-editor-ui-conventions]]` memory — HSplitView, unified `+/-/↑↓` toolbar, edit-immediate).
4. "Capture current" gesture walks `AXUIElementCreateApplication` for each running app, records each window's enclosing zone (or `nil` if none).
5. "Restore" walks the catalog and applies via the same `ChainedWindowMover` AutoRestore uses.

Worth considering before #27:
- **Add tests for Phase E.** No new unit tests landed in #24/#25/#26 (the overlays are mostly geometry + AppKit glue, hard to unit-test without an AppKit run-loop). `FrameResolver` math is already covered; consider extracting overlay zone-position math (`OverlayWindow.render`-equivalent) so it can be tested headless. Or accept that overlays are exercised only via the running app.
- **Close the Phase D loop.** `ArrangementRegistry.onMatched` still only logs; `AppDelegate.applicationDidFinishLaunching` line 33-39 has the callback. Surfacing "Arrangement: <name>" in the menu-bar dropdown is a 20-minute follow-up (`Mullion/UI/LayoutPickerMenu.swift:38-104` — actually was done in `29558f9`, the "auto-snap on match" piece is what's still open).

## Deferred / open
- **No Phase E tests.** Overlay controllers + tint provider are exercised only through the running app. See "worth considering" above.
- **`ModifierMask` chord coverage is partial.** `controlOption`, `controlShift`, `optionShift` exist; `commandOption`, three-key chords, etc. don't. Add as needed.
- **Wallpaper tint doesn't refresh on wallpaper change.** Sampled once per display on first overlay show, cached for the app's lifetime. Relaunch picks up new wallpapers. If a user complains, hook `NSWorkspaceActiveSpaceDidChangeNotification` or watch `desktopImageURL(for:)` for changes.
- **Settings UI for modifiers doesn't exist.** `dragSnapModifier` and `gridModifier` are persisted in `settings.json` and decode-with-default; no editor surface for changing them. Users have to hand-edit JSON until an editor lands.
- Phase D follow-up: behavioural application of `defaultLayoutID` (status-menu indicator beyond the name display, auto-snap on match, AutoRestore integration) is still unscoped. Today it's a log line only.
- `Mullion/Hotkeys/HotkeyBinding.swift:16` `case focus` marked "v1: stub" — intentional, deferred per design.
- `Mullion/UI/AppRulesEditorView.swift:234` Phase G escape hatch — intentional, deferred per design.
- `Mullion/Update/UpdaterController.swift:35` Sparkle disabled until `SUFeedURL`/`SUPublicEDKey` are configured. Holding for v1.0 first public release per [[mullion-release-pipeline]].

## How to verify
```
git log --oneline -5
git status
xcodegen generate
xcodebuild -project Mullion.xcodeproj -scheme Mullion -destination 'platform=macOS' test 2>&1 | grep "Executed.*tests" | tail -1
```

Expected: HEAD at `5efbe76` on `main` (no Phase E #26 commit yet — uncommitted in the working tree per **In-flight** above); clean tree apart from 3 modified + 2 new untracked files under `Mullion/Overlay/` + `Mullion/Settings/` + `Mullion/Core/`; `Executed 61 tests, with 0 failures`.

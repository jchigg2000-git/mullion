# Handoff — 2026-05-26 12:45 local

## What shipped (this session)
- `365540d` — fix: overlay placement on non-primary displays. `NSWindow(contentRect:..., screen:)` treats the `screen:` parameter as a hint, not authoritative — on multi-display setups Phase E drag and grid overlays were being created with the correct `.screen` reported but the surface was invisibly stacked on the primary display. Forcing `setFrame(screen.frame, display: false)` immediately after init makes macOS actually place the surface on the target display. Two-line fix in `DragOverlayController.OverlayWindow.init` and `GridOverlayController.GridOverlayPanel.init`. Verified via diagnostic logging: all three displays now report `vis=true` with correct cross-display absolute frames.
- `53841de` — feat: Phase F #27 Workspaces: capture + restore. New `Mullion/Layout/Workspace.swift` (Codable `WorkspaceItem` + `Workspace` + `WorkspaceCatalog`, versioned), `WorkspaceStore.swift` (`JSONStore<WorkspaceCatalog>` at `Application Support/Mullion/workspaces.json`), `WorkspaceController.swift` (capture walks running apps and records each window whose centre falls inside a zone on its display; restore matches by closest captured frame, falls back to title then first-remaining). New `Mullion/UI/WorkspacesEditorView.swift` sidebar section: edit-immediate name, Restore + Recapture buttons, per-item grid (App / Window / Display / Zone), restore-result feedback. Wired into `AppDelegate` (`workspaceStore` + lazy `workspaceController`) and `LayoutEditorModel` (sidebar selection, capture/restore/update/delete). 6 codable roundtrip + legacy-decode tests. 8 files, +675/-2 lines.
- `7736371` — feat: Phase F #28 Workspaces: arrangement binding. `Workspace.arrangementID: UUID?` field, `decodeIfPresent` for legacy files. When `ArrangementRegistry.onMatched` fires (launch or display change), `AppDelegate.autoRestoreBoundWorkspaces(for:)` looks up workspaces bound to the match and restores the most-recently-captured one via `WorkspaceController`, gated by `autoRestoreEnabled` + AX trust. New "Arrangement binding" section in the workspace detail with a `None`-sentinel picker; inline label flips to green when the bound arrangement is the current match. 2 binding-roundtrip + legacy-decode tests. 4 files, +126/-4. Tests: 69, all pass.

## Decisions (this session)
- **Workspace restore matches by closest captured frame, not by window title or AXWindowID.** iTerm titles every window the same string ("Default") so title-matching collapsed on the very first smoke test. AXWindowID is private API and we don't depend on it elsewhere. The captured frame is the most reliable per-window identifier we can persist without going off-API. Falls back to title-match (when capturedFrame absent — legacy files) and then to first-remaining.
- **Multiple workspaces bound to one arrangement: most-recently-captured wins.** Legal but ambiguous state; `capturedAt` is the most defensible tiebreaker. Recapture acts as "this is now the one."
- **Auto-restore fires both at launch and on every arrangement-match transition.** Launch path is the explicit call inside the existing `autoRestoreEnabled && AX-trusted` block in `applicationDidFinishLaunching` (the `recompute()` earlier fires before the callback is wired, so the callback alone wouldn't catch launch). Display-change path is the `onMatched` callback. Both gated by the same two conditions.
- **`WorkspaceController` lives outside the editor model.** Phase F #28 calls it directly from `AppDelegate`; the editor model proxies through it. Keeps the capture/restore engine independent of the UI surface.
- **Overlay diagnostic logging was added then removed.** The `debugSnapshot` accessor + per-show log line confirmed the multi-display fix; once verified, both were stripped to keep the regular drag/grid log tidy. The `setFrame` fix + a one-paragraph comment explaining why is what stayed.

## Don't break
- **`Workspace.arrangementID` is optional Codable with `decodeIfPresent`.** Older workspaces.json files (no `arrangementID`, or `WorkspaceItem` without `capturedAXFrame`) must keep loading. Schema bumps go through the same pattern.
- **Workspace `recapture` does a throwaway-then-delete dance.** `LayoutEditorModel.recaptureWorkspace` calls `workspaceController.captureCurrent` (which persists a new workspace), then immediately removes that disposable workspace and upserts the original id with the new items. Not transactional — if the app crashes between the throwaway capture and the remove, you'd end up with two workspaces. JSONStore's 500ms debounce shrinks the disk window further, but it's not guaranteed. Worth refactoring `WorkspaceController.captureCurrent` to take an "in-place-on" parameter if this matters.
- **Auto-restore order at launch: AppRule/Learned (existing `AutoRestore`) runs first, then bound-workspace restore.** Workspace is more specific — it overrides AppRule placements where the two collide. If a workspace doesn't capture a given window, AppRule's placement for that window stands.
- **Multi-display overlay placement requires `setFrame(screen.frame, display: false)` AFTER init.** The `screen:` init argument is documented as a hint and macOS silently ignores it on non-primary displays. Adding a new overlay-controller-style surface? Copy the pattern from `DragOverlayController.OverlayWindow.init` / `GridOverlayController.GridOverlayPanel.init`.
- **After adding files in `Mullion/`, run `xcodegen generate` before `xcodebuild`.** `Mullion.xcodeproj/project.pbxproj` is gitignored.

## Next session: start here

**Phase F is complete.** From `docs/design/v1.md`, the remaining build-order item is:

- **Step #29 — `SystemWindowManager` fallback (Phase G, conditional).** Gated entirely behind `compatibilityProfile == .systemWindowManager`. Half/third support only. **Build only if a real user reports an app where the AX path can't be made to work.** No known requestor yet, so this is hold-for-demand, not next-session work.

So the actual next thing is either:
1. **v1.0 release pipeline.** Per `[[mullion-release-pipeline]]`: wired + smoke-tested, holding for v1.0 tag. Requires DEVELOPER_ID_APP + NOTARY_KEYCHAIN_PROFILE + SUFeedURL/SUPublicEDKey before Sparkle goes live. See `docs/release.md` + `scripts/release.sh`.
2. **Polish pass before public release.** Settings UI for `dragSnapModifier` / `gridModifier` (currently hand-edit `settings.json`); wallpaper-tint refresh on `NSWorkspaceActiveSpaceDidChangeNotification`; status-menu "Arrangement: \<name\>" already lands via `29558f9` but auto-snap-on-match (apply `defaultLayoutID` behaviourally beyond the workspace path) is still log-only.
3. **Light-touch test coverage.** Phase E overlay controllers + `WorkspaceController` capture/restore are exercised only through the running app. Pure-math extraction would let them run under XCTest without an AppKit run loop.

## Deferred / open
- **No tests for Phase E overlays.** Same as last handoff — `DragOverlayController`, `GridOverlayController`, `WallpaperTintProvider` only via the running app.
- **No tests for `WorkspaceController.captureCurrent` / `restore`.** Same reason — needs running apps + AX. The Codable surface is covered.
- **`WorkspaceController.recapture` is non-atomic.** See "Don't break" above.
- **Phase D follow-up: behavioural application of `defaultLayoutID`.** Today `arrangementRegistry.onMatched` fires for any default layout, but `AppDelegate` only logs it (auto-snap on match, AutoRestore-style apply, etc. still TBD). Phase F #28 wires a parallel workspace path; the layout path is still log-only.
- **Settings UI for `dragSnapModifier` / `gridModifier`.** Hand-edit `settings.json` until an editor lands.
- **Wallpaper tint doesn't refresh on wallpaper change.** Sampled once per display on first overlay show, cached for the app's lifetime.
- **`ModifierMask` chord coverage is partial** (`controlOption`, `controlShift`, `optionShift` only). Add as needed.
- **Sparkle feed disabled.** `Mullion/Update/UpdaterController.swift:35` — holding for v1.0 first public release per [[mullion-release-pipeline]].
- **`Mullion/Hotkeys/HotkeyBinding.swift:16` `case focus`** marked "v1: stub" — intentional, deferred per design.
- **`Mullion/UI/AppRulesEditorView.swift:234` Phase G escape hatch** — intentional, deferred per design.

## How to verify
```
git log --oneline -5
git status
xcodegen generate
xcodebuild -project Mullion.xcodeproj -scheme Mullion -destination 'platform=macOS' test 2>&1 | grep "Executed.*tests" | tail -1
```

Expected: HEAD at `7736371` on `main`; clean tree; `Executed 69 tests, with 0 failures`.

# Handoff — 2026-05-26 13:14 local

## What shipped (this session)
- **`ArrangementRegistry.recompute` now gates `onMatched` / `onUnknown` on actual match transitions.** Previously fired on every `recompute()` call — and `reloadAll()` (triggered by FSEvents on `window-history.json` from grid-snaps + drag-snaps) calls `recompute()`. Net effect: every user-initiated window move was triggering a full bound-workspace restore ~250ms later, yanking everything back. The gate compares `match.id` to a captured `previousMatchID`; same-arrangement recomputes are silent. `Mullion/Display/ArrangementRegistry.swift:51-71`.
- **`WorkspaceController.restore` now skips items whose window is already at target.** Tolerance `< 2` AX points per axis, matches `StandardWindowMover`'s success threshold. Avoids no-op AX writes on the legitimate-restore path (manual Restore button, re-plug after windows already placed, etc.) — those would otherwise still flash focus / animate. `Mullion/Layout/WorkspaceController.swift:159-167` + helper at line 217.
- **Diagnostic logging in both paths.** `autoRestore-entry/skip/bound/fire` in `AppDelegate.autoRestoreBoundWorkspaces` (now takes `trigger:` so launch vs onMatched is distinguishable). `restore-begin/end/bundle/item/skip-*` in `WorkspaceController.restore` with full before/target/after AX frames and pre/post deltas. Kept at `.notice` for v1 dogfooding; demote to `.debug` post-launch.

## Decisions (this session)
- **Shipped both fixes, not just the primary.** Original instinct was to ship only the transition gate (the loop killer) and defer idempotence as "rare path." Wrong call: (a) my own prior-session handoff note had queued idempotence as a candidate fix; (b) manual Restore button / re-plug are normal triggers that would still flash without it; (c) the diff was tiny. User pushed back, correctly.
- **Logging stays in for v1.** Volume is fine — restore now fires rarely. Once v1 is out, demote the per-item lines to `.debug`.
- **No new tests for `ArrangementRegistry.recompute` transition gating.** Would need a fake `DisplayRegistry` (currently a `final class` with `nonisolated init()` pulling from `NSScreen.screens`); too much harness for too small a payoff. Manual reproduction via the bug-hunt log was conclusive.

## Don't break
- **`ArrangementRegistry.recompute` only fires on transitions.** Any future caller that *needs* a fresh `onMatched` fire (e.g., a hypothetical "reapply default layout for current arrangement" command) must invoke the callback directly, not call `recompute()` and expect a refire.
- **`WorkspaceController.framesEqualWithinTolerance` uses `< 2`** to match `StandardWindowMover`'s success threshold. Keep them in sync — if one threshold changes, the other should.
- (Carried forward) **`Workspace.arrangementID` is optional Codable with `decodeIfPresent`**; **`WorkspaceController.recapture` is non-atomic**; **multi-display overlay placement requires `setFrame(screen.frame, display: false)` after init**; **xcodegen generate before xcodebuild** after adding files in `Mullion/`.

## Next session: push for v1.0
**That's the only headline.** Release pipeline is wired and smoke-tested per `[[mullion-release-pipeline]]`; credentials are all in place. What's left is decision + manual mechanics:
1. Confirm version (probably `1.0.0`).
2. Draft release notes — no `CHANGELOG.md` exists yet; needs a 4–8 bullet summary covering layouts, hotkeys, app rules, arrangements, drag-to-snap, grid overlay, workspaces.
3. `VERSION=1.0.0 DEVELOPER_ID_APP="..." NOTARY_KEYCHAIN_PROFILE=mullion-notary make release` — outputs `release-build/Mullion-1.0.0.dmg` + appcast snippet.
4. `git tag v1.0.0 && git push --tags`.
5. Create GitHub Release at `github.com/jchigg2000-git/mullion`, upload DMG.
6. Paste appcast `<item>` snippet into `docs/appcast.xml`, commit, push (GitHub Pages republishes).
7. Pre-flight: `spctl --assess --verbose=4 release-build/Mullion-1.0.0.dmg`.

## Deferred / open (post-v1)
- **Discord refuses to resize on restore.** Mover returns `moverOK=true` but Discord stays at original height (Electron min-height enforcement). Captured in the 2026-05-26 bug-hunt log. Candidate fix: a "respect-min-size" `CompatProfile` flag.
- **Finder window 3 (fullscreen-ish 4072×2160) won't move.** Same shape as Discord — mover lies; window in fullscreen Space probably can't be AX-moved at all.
- **iTerm sidebar off-by-1px** (`dx=-1`). Now masked by the idempotence guard (`< 2` tolerance), but underlying rounding lives in `FrameResolver` / `Geometry`.
- **Settings UI for `dragSnapModifier` / `gridModifier`.** Still hand-edit `settings.json`. Sketched + reverted this session; pickup is straightforward.
- **Wallpaper tint doesn't refresh on wallpaper / space change.** Sampled once per display on first overlay show, cached for app lifetime.
- **Phase D follow-up — behavioural application of `defaultLayoutID`.** `onMatched` logs the default layout but doesn't apply it (only the workspace path acts on match).
- **No tests for Phase E overlays / `WorkspaceController` capture/restore** — only exercised via the running app.
- **`WorkspaceController.recapture` is non-atomic.**
- **`ModifierMask` chord coverage is partial** (`controlOption`, `controlShift`, `optionShift`).
- **Sparkle feed disabled** — `Mullion/Update/UpdaterController.swift:35`; flips on with the v1.0 Info.plist update.
- **`HotkeyBinding.swift:16` `case focus` "v1: stub"** — intentional, deferred.
- **`AppRulesEditorView.swift:234` Phase G escape hatch** — intentional, deferred.
- **`SystemWindowManager` fallback (step #29, Phase G)** — hold-for-demand.
- **Diagnostic logging volume.** Per-item `restore-item` lines are verbose. Demote to `.debug` after the v1 launch settles.

## How to verify
```
git log --oneline -5
git status
xcodegen generate
xcodebuild -project Mullion.xcodeproj -scheme Mullion -destination 'platform=macOS' test 2>&1 | grep "Executed.*tests" | tail -1
```
Expected: HEAD on `main`; clean tree; `Executed 69 tests, with 0 failures`.

To watch the auto-restore path live:
```
/usr/bin/log stream --predicate 'subsystem == "com.mullion.Mullion"' --info --style syslog
```
With the transition gate in place, `arrangement matched:` should only appear on real display reconnects — not on every grid-snap.

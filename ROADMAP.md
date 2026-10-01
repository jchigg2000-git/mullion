# Mullion — ROADMAP

> ⭐ **SINGLE SOURCE OF TRUTH.** On any handoff or fresh session, **read this first and follow
> only this** for what's left, what's next, phases, acceptance criteria, and decisions. There are
> **no other `*_PLAN` / handoff docs** — `docs/handoff.md` was consolidated into this file
> (2026-08-07). If another doc's status ever conflicts with this one, **this wins.**
>
> - **Strategy / the "why"** (a different layer, not an execution plan): none separate — the
>   README covers product framing.
> - **Reference / spec** (opened on demand, never as "the plan"): `docs/design/v1.md` (architecture,
>   key types, persistence schema, risk register — still accurate, kept separate); `docs/release.md`
>   (live deploy contract — signing/notarization/Sparkle process, do not fold).
> - **Decisions**: `DECISIONS.md` (append-only log; roadmap items cite it by date + title).

**Legend:** ✅ done · 🔶 shipped but UNVERIFIED · ⏳ in progress · ⬜ not started · 🔬 verification
owed · 🔁 superseded (kept for its evidence, not as work) · ⛔ **BLOCKS** — the only marker that
gates anything

**Contents:** §0 Do next · §1 Post-v1 cleanup queue · §2 Known limitations / polish · §3 Deferred
(P2) · §4 Build-order index (historical) · §5 Open-decisions index · Appendix

---

## §0 Do next

> ### ▶ RESUME HERE — 2026-09-26: display-change fixes on `main`, live check owed, NOT released
>
> **State:** the parked branch `fix/display-change-resilience` (on top of v1.0.1 @ `f90b1c2`)
> was merged to `main` on 2026-10-01 by the repo-sweep loop (86 tests green at merge). Owner
> had parked it mid-verification — windows being rearranged during testing was interfering
> with other work. Not released. **Nothing here is a blocker for anything else.**
>
> **▶ NEXT ACTION:** finish the owner-run live check (undock → redock with a dev build of
> `main`, one ⌃⌥ grid click + one ⌃-drag per display after each) before cutting 1.0.2 via
> `docs/release.md`. Optionally run one more opus review round first (round 2 was stopped
> before it reported).
>
> #### What the merge brought
> - `0d3bea4` docs(release): Homebrew cask bump step (from another session; owner OK'd shipping it).
> - `8af76a9` the fixes: re-arm the mouse event tap on `tapDisabledByTimeout/ByUserInput` and
>   re-check it on display change + display wake; grid clicks resolved from the tap against
>   live geometry (`Overlay/ZoneHitTest.swift`, shared with drag-to-snap) instead of cached
>   panels with a stale `owningScreen`; overlays re-framed on every render; process-wide 1 s
>   AX messaging timeout; `ConfigFileWatcher` no longer reloads on `window-history.json` writes;
>   `WindowMutator` keeps EUI off through the aggressive retry; `.notice` logs for display
>   changes, mutator retries, tap re-arms and every grid no-snap path.
> - `5f0b3db` opus review round 1: grid clicks pick the zone drawn on top (my first cut picked
>   the first match — a full-screen zone listed first swallowed every quadrant click);
>   watcher reloads on FSEvents rescan/dropped/dir-level notices; an unmodified click dismisses
>   a grid left stuck by a lost ⌃⌥ release. 86 tests green.
>
> #### Evidence (unified log, 2026-09-26)
> - "Close and reopen after docking": after the 13:00 dock event the grid never revealed again
>   until relaunch — tap disabled, never re-armed. **Reproduced live on the dev build at
>   16:50:52**: a slow-to-answer app stalled a snap, macOS logged the tap disabled by timeout,
>   the new handler re-enabled it and the next snap worked.
> - Two other relaunches (no display change) had "grid revealed" with no snap and no log line:
>   clicks went through cached panels' own hit-testing. Now tap-driven and logged.
> - Every snap triggered a full `reloadAll` ~0.8 s later via the `window-history.json` write.
>
> #### Still open
> - 🔬 **TWITCH-1** "screen twitching / pixels drifting off-screen or into the Dock after a dock
>   change; shrinking windows usually stops it." **Not reproduced.** One docking run with a
>   10 Hz CGWindowList probe found only macOS Mission Control / Spaces animations (all windows
>   in lockstep) and no Mullion frame writes. Code review refuted a frame-write feedback loop
>   (Mullion has no AXObserver) and a stale coordinate pivot. The EUI-retry double jump is fixed.
>   Next time it happens: note the time, then read `log show --predicate 'subsystem ==
>   "com.mullion.Mullion"'` around it (`displays` / `mutator` categories) — Mullion's
>   `.notice` lines only survive a few hours in the unified log.
>   **Evening 2026-09-26, three live captures while the owner reproduced it** (window bounds at
>   10–20 Hz incl. Dock layers + cursor, frontmost-app changes, Dock `com.apple.dock.spaces`):
>   Mullion logged nothing and wrote no frames in any of them. Every desktop flip coincided
>   with an app activation; two were explicit — Dock: "switching to space N for window …
>   ordered on non-visible space" for **Messages** (20:55:07) and **Claude** (20:51:28,
>   20:55:29) — i.e. macOS "When switching to an application, switch to a Space with open
>   windows" (on by default here). The Dock bar window (L20, full LG frame) never moved;
>   Dock magnification is on (49 → 84 pt), which redraws inside that window and is invisible
>   to CGWindowList. Untested lead matching the owner's "position of a window" hunch: zones
>   end flush at `visibleFrame` bottom, so a click near a lower zone's bottom edge grazes the
>   magnification zone. Cheapest A/B next time: quit Mullion and repeat; then try with that
>   Spaces setting off and/or magnification off (or a `outerMargin.bottom` on lower zones).
> - ⬜ Not fixed (judged real but deferred by the review): grid hit-test is geometry-only, so a
>   click on a fully transparent panel pixel could still snap — marginal; tap re-arm doesn't
>   resync modifier state (`CGEventSource.flagsState`), so a stuck grid stays painted until the
>   next click.
> - Setup note, not a bug: the saved "3 displays" arrangement doesn't match when the 2560×720
>   display is off, so the 2-display dock gets no default layout / workspace auto-restore. The
>   menu offers "Save current displays as arrangement…".
> - The new diagnostic `.notice` lines deliberately run against CLEAN-4 below — keep them until
>   TWITCH-1 is closed.
>
> #### Carried from the 2026-08-07 handoff
> - `docs/design/v1.md` "Build order" is stale (Phases A–F all shipped); only Phase G #29 unbuilt.
> - `HotkeyBinding.swift:16` comment `// v1: stub` on `case focus` is stale.
---

## §1 Post-v1 cleanup queue

Folded from `docs/handoff.md` § "Post-v1 cleanup queue." All still open — none had a fixing
commit in `git log`.

- ✅ **CLEAN-1** (**DONE `f90b1c2`** — Sparkle's copy is stripped, template's kept) `scripts/release.sh` emits a duplicated `length` attribute in the appcast
  snippet — `scripts/release.sh:191` hardcodes `length="$SIZE_BYTES"`, then line 193 pastes
  `$SPARKLE_SIG_LINE` which already contains its own `length="..."`. Confirmed still present at
  both line numbers. One-line fix: drop the script's own `length=` line.
- ⬜ **CLEAN-2** `scripts/release.sh:83` pipes through `xcpretty`, which isn't installed —
  confirmed still present (`archive | xcpretty || true`). Non-fatal (falls through to raw
  output). `brew install xcpretty` or remove the pipe.
- ⬜ **CLEAN-3** Only the DMG is stapled, not the `.app` inside it — confirmed:
  `scripts/release.sh:146-147` staples/validates `$DMG_PATH` only. Gatekeeper does an online
  notarization check on first launch after copy-from-DMG; works, but isn't offline-safe.
  Reorder: notarize → staple the `.app` → repackage DMG → submit → staple DMG (or simplest:
  `xcrun stapler staple` on the `.app` post-notarize).
- ⬜ **CLEAN-4** Demote dogfooding-era diagnostic logging from `.notice` to `.debug` —
  `autoRestore-entry/skip/bound/fire` (`AppDelegate.swift`, confirmed still `.notice` at lines
  46/57/61/107/181/184/188/190/193/222) and the equivalent in `WorkspaceController`. Deferred
  until a few real users are running it without surprises.

## §2 Known limitations / polish (P1)

Folded from `docs/handoff.md` § "Deferred / open — P1," cross-checked against
`CHANGELOG.md`'s "Known limitations" for 1.0.0 (which independently confirms the first two).

- ⬜ **LIMIT-1** Discord (and similar Electron apps with hard min-size constraints) silently
  ignores AX resize on restore — the AX call reports success but the window snaps back.
  Candidate fix: a `respect-min-size` `CompatProfile` case (current cases per
  `Compat/CompatProfile.swift`: `.standard`, `.aggressive`, `.systemWindowManager` — no
  min-size-aware case exists yet).
- ⬜ **LIMIT-2** Finder in a fullscreen Space won't move — AX-resistant, possibly inherent to
  fullscreen Spaces.
- ⬜ **LIMIT-3** iTerm sidebar off-by-1px (`dx=-1`) — masked by the `< 2` idempotence tolerance
  in `WorkspaceController.framesEqualWithinTolerance`, but the rounding source lives in
  `FrameResolver`/`Geometry`. Not independently re-verified this pass; carried forward.
- ⬜ **LIMIT-4** Wallpaper tint for the grid overlay doesn't refresh on wallpaper/Space change —
  sampled once per display on first overlay show, cached for the app's lifetime. Confirmed
  still true in `CHANGELOG.md`'s 1.0.0 known-limitations list; no fix commit since.
- ~~⬜ **LIMIT-5 — Settings UI for `dragSnapModifier`/`gridModifier` still hand-edited via
  `settings.json`.**~~ **DONE `e423244`** — "feat: Preferences pane for drag-snap & grid overlay
  modifiers," shipped after `docs/handoff.md` was written; README already documents it. Original
  text: *"Settings UI for the drag-snap / grid-overlay modifier keys is pending; for now edit
  `~/Library/Application Support/Mullion/settings.json` directly."*

## §3 Deferred (P2)

Folded from `docs/handoff.md` § "Deferred / open — P2."

- ✅ **DEFER-1** Arrangement match doesn't behaviorally apply `defaultLayoutID` — **DONE in 1.0.1
  (`e5b56d9`)**: `onMatched` now sets `layoutStore.preferredLayoutID`, which governs layout
  resolution (see `CHANGELOG.md` 1.0.1).
- 🔬 **OWED — does the "non-atomic" concern on workspace capture still apply?** `docs/handoff.md`
  named `WorkspaceController.recapture` as non-atomic; that method doesn't exist under that name
  anymore — current code has `captureCurrent(name:)` (`WorkspaceController.swift:33`). Unclear
  whether this is a rename of the same code path or a rewrite that resolved the concern. Asked,
  not answered; do not treat as closed either way.
- ⬜ **DEFER-2** `ModifierMask` chord coverage described as "partial" (`controlOption`,
  `controlShift`, `optionShift`) — the enum itself (`Settings/AppSettings.swift:18-20`) defines
  all three cases, so the gap (if any) is in what's exposed in UI, not the data model. Not
  independently re-verified past that; carried forward as-is.
- ⬜ **DEFER-3** No tests for the Phase E overlays or `WorkspaceController` capture/restore —
  only exercised via the running app.
- ✅ **DEFER-4** (superseded framing) `SystemWindowManager` fallback (build-order item #29,
  "Phase G") — genuinely unbuilt, confirmed by `CompatProfile.swift:16`'s own comment: "Treated
  as `.standard` by the mutator until Phase G ships." **Status: BACKLOG. Not a blocker.**
  Explicitly hold-for-demand — build only if a real user reports an app the AX path can't
  handle. No owner instruction exists naming this a blocker on anything else.

## §4 Build-order index (historical)

Reference: `docs/design/v1.md` § "Build order" carries the full numbered list (1–29) and the
original architecture reasoning for each phase — kept in place, not reproduced here. Corrected
shipped/open status, verified against source and `git log` this pass:

- ✅ **Phase 0** (steps 1–14, the original v1 core) — shipped, per `docs/design/v1.md` and
  confirmed by `CHANGELOG.md` 1.0.0.
- ✅ **Phase A** (steps 15–16: `.focus` role, `outerMargin`/`innerGap`) — shipped. `.focus`
  dispatches via `FocusIndex` (`ActionDispatcher.swift:75`) despite a stale "v1: stub" comment
  on the enum case; `outerMargin`/`innerGap` implemented in `FrameResolver.swift` and exposed in
  `LayoutEditorView.swift:375-387`.
- ✅ **Phase B** (step 17: Sparkle + notarization) — shipped, v1.0.0 released 2026-05-26.
- ✅ **Phase C** (steps 18–21: App Rules editor UI, Bindings editor UI, FSEvents auto-reload,
  `compatibilityProfile` field) — shipped: `AppRulesEditorView.swift`, `BindingsEditorView.swift`,
  `ConfigFileWatcher.swift` all exist and are wired.
- ✅ **Phase D** (steps 22–23: arrangement detection, arrangement → default layout) — detection
  is shipped (`ArrangementRegistry.swift`); the "apply default layout on match" half is **not**
  fully wired — see **DEFER-1** in §3. `docs/design/v1.md` calls step 23 "the first end-to-end
  arrangement-as-unit milestone," which overstates current behavior; only the workspace-binding
  path actually applies anything on a match today.
- ✅ **Phase E** (steps 24–26: mouse event tap, drag-to-snap overlay, hold-modifier grid
  overlay) — shipped, commits `7ef78e9`, `5efbe76`, `9682b52`.
- ✅ **Phase F** (steps 27–28: workspaces capture/restore, arrangement binding) — shipped,
  commits `53841de`, `7736371`.
- ⬜ **Phase G** (step 29: `SystemWindowManager` fallback) — not built. See **DEFER-4** in §3.

## §5 Open-decisions index

- 🔬 OWED (§3 DEFER-1 note): does `WorkspaceController.captureCurrent` resolve the atomicity
  concern originally raised about `recapture`, or is it still open under the new name?

---

## Appendix — consolidation history

Fold performed by hand (repo has no `roadmap` skill target — `~/.claude/skills/doc-consolidation`
run against `~/Projects/mullion`, 2026-08-07). HEAD at fold time: `a59ba2f`.

- `docs/handoff.md` (86 lines, dated 2026-05-26) — folded into §0 (as the prior-state summary),
  §1 (post-v1 cleanup queue), §2/§3 (deferred items), and the "Don't break" invariants list
  folded into `DECISIONS.md`. **Staged to purgatory**, not deleted — recoverable via
  `git show a59ba2f:docs/handoff.md`. The `handoff-to-next` skill is retired; this doc's role
  moves to this file's §0 going forward.
- `CHOICES.md` (54 lines) — every entry appended to `DECISIONS.md` verbatim (grouped by the same
  headings). **Staged to purgatory**, not deleted — recoverable via
  `git show a59ba2f:CHOICES.md`.
- `docs/design/v1.md` (416 lines) — **not folded, not staged, left in place unedited.** Still the
  accurate architecture/schema/risk-register reference and actively linked from `README.md`. Its
  "Build order" section sequences work and is partially stale (see §0/§4 above); the corrected
  status now lives here rather than being rewritten in place, per doc-consolidation's
  fold-the-sequencing-leave-the-reasoning rule — the reasoning half stays where it is.
- `docs/release.md` (151 lines) — **not folded, not staged, left in place.** Live Sparkle /
  notarization / release-process contract, not a plan doc.
- `README.md`, `CLAUDE.md` (pre-existing content), `CHANGELOG.md`, `CONTRIBUTING.md` — untouched,
  never-touch canonical surface.

Not migrated: none. Everything in `docs/handoff.md` and `CHOICES.md` is accounted for above.

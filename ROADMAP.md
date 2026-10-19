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

> **Closed work is not in this file.** An item is deleted at the edit that closes it — there is
> no ✅ status. What shipped is recorded by the closing commit and `CHANGELOG.md`. To resurrect
> or cite a deleted item: `git log -S'<ID>' -- ROADMAP.md`, then `git show <sha>:ROADMAP.md`.

**Legend:** 🔶 shipped but UNVERIFIED · ⏳ in progress · ⬜ not started · 🔬 verification owed ·
⛔ **BLOCKS** — the only marker that gates anything

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
>   **2026-10-13, one Mullion cause found and fixed on `main`.** Dock at 15:57:11 → LG hotplug
>   out 15:58:00.5 (power source flipped too: the whole dock link dropped) → laptop-only
>   "Macbook Claude Code" matched 15:58:01.1 and auto-restore moved 6 iTerm/Finder windows
>   at once → LG back 15:58:03.0 and macOS moved them again. Fix: `ArrangementRegistry`
>   now has `onSettled`, which fires only once a match has held for 4 s with no further
>   display change, and auto-restore hangs off that instead of `onMatched`; a blip that comes
>   back to the arrangement that held before it restores nothing (114 tests green, not
>   live-verified; the redock check should look for `did not settle` / `came back before
>   anything else settled` in the `arrangements` log category). Nothing at the owner's "lots of twitching right now" (16:08): a
>   5-minute 10 Hz probe from 16:09:12 saw no frame, display or Space change and no Mullion log,
>   so that episode was pixel-level, not windows moving. Still open on that strand.
> - ⬜ Not fixed (judged real but deferred by the review): grid hit-test is geometry-only, so a
>   click on a fully transparent panel pixel could still snap — marginal.
> - 🔶 Tap re-arm now resyncs modifier state (`MouseEventTap.resyncModifiers()` reads
>   `CGEventSource.flagsState` after every re-enable and feeds it through `onFlagsChanged`), so a
>   ⌃⌥ release lost while the tap was off hides the grid instead of leaving it painted until the
>   next click. Landed on `main` 2026-10-01 (90 tests green); like the rest of the display-change
>   work, not live-verified.
> - 🔶 Landed on `main` 2026-10-01 (105 tests green; none live-verified): the matched
>   arrangement's default layout is now read live from `ArrangementRegistry.currentMatch`
>   (it was never applied at launch, ignored on edit, and kept after leaving the arrangement) —
>   so the redock check should also confirm ⌃⌥ grid / ⌃⌥N use the arrangement's default layout;
>   `JSONStore` copies an unreadable config aside as `<name>.json.unreadable-<ts>` before
>   overwriting it and flushes pending writes on quit; workspace capture tries the governing
>   layout first; drag and grid snaps feed the per-zone `.focus` list (`SnapRecorder`).
> - 🔶 Drag-to-snap no longer AX-hit-tests the window under **every** left click (it ran inside
>   the tap callback, so one slow app could stall the tap past its timeout — a likely feeder of
>   the "tap disabled by timeout" evidence above). Only a press with the drag modifier resolves
>   at mouseDown; a modifier added mid-drag resolves once at the cursor. Landed on `main`
>   2026-10-01 (`DragOverlayControllerTests`), not live-verified: the redock check should
>   include one ⌃-drag where ⌃ is pressed *after* the drag starts.
> - Setup note, not a bug: the saved "3 displays" arrangement doesn't match when the 2560×720
>   display is off, so the 2-display dock gets no default layout / workspace auto-restore. The
>   menu offers "Save current displays as arrangement…".
> - The new diagnostic `.notice` lines deliberately run against CLEAN-4 below — keep them until
>   TWITCH-1 is closed.

---

## §1 Post-v1 cleanup queue

- ⬜ **CLEAN-3** Only the DMG is stapled, not the `.app` inside it — confirmed:
  `scripts/release.sh:156-157` staples/validates `$DMG_PATH` only. Gatekeeper does an online
  notarization check on first launch after copy-from-DMG; works, but isn't offline-safe.
  Reorder: notarize → staple the `.app` → repackage DMG → submit → staple DMG (or simplest:
  `xcrun stapler staple` on the `.app` post-notarize).
- ⬜ **CLEAN-4** Demote dogfooding-era diagnostic logging from `.notice` to `.debug` —
  `autoRestore-entry/skip/bound/fire` (`AppDelegate.swift`, confirmed still `.notice` at lines
  50/74/82/128/231/234/238/240/243/272) and the equivalent in `WorkspaceController`. Deferred
  until a few real users are running it without surprises.

## §2 Known limitations / polish (P1)

- ⬜ **LIMIT-1** Discord (and similar Electron apps with hard min-size constraints) silently
  ignores AX resize on restore — the AX call reports success but the window snaps back.
  Candidate fix: a `respect-min-size` `CompatProfile` case (current cases per
  `Compat/CompatProfile.swift`: `.standard`, `.aggressive`, `.systemWindowManager` — no
  min-size-aware case exists yet).
- ⬜ **LIMIT-2** Finder in a fullscreen Space won't move — AX-resistant, possibly inherent to
  fullscreen Spaces.
- 🔶 **LIMIT-3** iTerm sidebar off-by-1px (`dx=-1`) — **fixed on `main` 2026-10-01, not
  live-verified.** The source was `FrameResolver` emitting fractional zone edges (e.g. a third
  of 1512 = 503.99…) that the window server truncated; it now snaps every edge to a whole point
  (`FrameResolver.snappedToWholePoints`), so shared boundaries stay flush. The `< 2` restore
  tolerance stays as a safety net. Covered by `FrameResolverTests`.

## §3 Deferred (P2)

- ⬜ **DEFER-3** No tests for the Phase E overlays or `WorkspaceController` capture/restore —
  only exercised via the running app. (Only capture's store-write contract is covered, by
  `WorkspaceControllerTests`; the AX walk, zone matching and restore are not.)
- ⬜ **DEFER-4** `SystemWindowManager` fallback (build-order item #29,
  "Phase G") — genuinely unbuilt, confirmed by `CompatProfile.swift:16`'s own comment: "Treated
  as `.standard` by the mutator until Phase G ships." **Status: BACKLOG. Not a blocker.**
  Explicitly hold-for-demand — build only if a real user reports an app the AX path can't
  handle. No owner instruction exists naming this a blocker on anything else.

## §4 Build-order index (historical)

Reference: `docs/design/v1.md` § "Build order" carries the full numbered list (1–29) and the
original architecture reasoning for each phase — kept in place, not reproduced here. Its status
is stale: Phases 0 and A–F (steps 1–28) all shipped; only Phase G (#29) is unbuilt.

- ⬜ **Phase G** (step 29: `SystemWindowManager` fallback) — not built. See **DEFER-4** in §3.

## §5 Open-decisions index

None open.

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
  "Build order" section sequences work and is partially stale (see §4 above); the corrected
  status now lives here rather than being rewritten in place, per doc-consolidation's
  fold-the-sequencing-leave-the-reasoning rule — the reasoning half stays where it is.
- `docs/release.md` (151 lines) — **not folded, not staged, left in place.** Live Sparkle /
  notarization / release-process contract, not a plan doc.
- `README.md`, `CLAUDE.md` (pre-existing content), `CHANGELOG.md`, `CONTRIBUTING.md` — untouched,
  never-touch canonical surface.

Not migrated: none. Everything in `docs/handoff.md` and `CHOICES.md` is accounted for above.

- 2026-10-12 trim to the open set (prose-upkeep 2026-W42, `cleanup-roadmap --roadmap-only`
  rules): deleted 12 closed entries (CLEAN-1, LIMIT-5, DEFER-1, workspace-capture OWED,
  DEFER-2, build-order Phases 0 and A–F) and 6 past-session remnants (a shipped-docs bullet,
  three "Folded from `docs/handoff.md`" intros, a resolved-question note, a handoff heading whose
  `v1.md` finding moved to §4); re-marked 4 done-but-unverified items 🔶 and DEFER-4 ⬜ (BACKLOG).
  Pre-trim file: `git show 253362c:ROADMAP.md`.

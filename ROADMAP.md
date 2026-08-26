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

> ### ▶ RESUME HERE — session handoff 2026-08-07 (doc-consolidation sweep)
>
> **State:** `main`, HEAD `a59ba2f` ("docs: refresh README"), tree clean before this sweep ran.
> No feature work happened this session — this was a documentation-consolidation pass only
> (`~/.claude/skills/doc-consolidation`). Current app version is 1.0.0 (`project.yml:53`,
> matches the only git tag `v1.0.0`).
>
> **▶ NEXT ACTION: pick any item from §1 (cheapest) or §2/§3 (real user-facing polish).**
>
> #### What shipped
> - This sweep: `ROADMAP.md` + `DECISIONS.md` + a `CLAUDE.md` SSOT paragraph, installed by hand
>   (repo had no pre-existing roadmap doc). `docs/handoff.md` and `CHOICES.md` folded in and
>   staged to purgatory (30-day review window) — no code changed.
>
> #### What I found by reading that nobody reported
> - **`docs/design/v1.md`'s "Build order" section is stale.** It frames Phases A–F (items
>   15–28: `.focus` role, `outerMargin`/`innerGap`, App Rules + Bindings editor UI, FSEvents
>   auto-reload, arrangement detection + default-layout apply, mouse tap, drag/grid overlays,
>   workspaces capture/restore/arrangement-binding) as "the remaining v1 work." **All of it is
>   shipped** — verified by reading source (`FocusIndex.swift`, `ActionDispatcher.swift:75`,
>   `FrameResolver.swift`, `AppRulesEditorView.swift`, `BindingsEditorView.swift`,
>   `ConfigFileWatcher.swift`, `ArrangementRegistry.swift`, `MouseEventTap.swift`,
>   `Drag/GridOverlayController.swift`, `WorkspaceController.swift`) and cross-checked against
>   `git log --oneline` (commits `5efbe76`, `9682b52`, `7736371`, `7ef78e9`, `7d27eed` etc. are
>   literally titled `feat: Phase E/F #NN — ...`). Only **Phase G item #29
>   (`SystemWindowManager` fallback)** is genuinely unbuilt — `CompatProfile.swift:16` says so
>   explicitly in a code comment ("Treated as `.standard` by the mutator until Phase G ships"),
>   and it's declared hold-for-demand, not scheduled.
> - **`HotkeyBinding.swift:16`'s comment `// v1: stub` on `case focus` is itself stale.**
>   `ActionDispatcher.swift:75` dispatches `.focus` for real, through `FocusIndex`'s MRU list.
>   Left the comment alone — a code-comment fix is outside a doc-consolidation sweep's scope, but
>   flagging it here so it doesn't get taken at face value.
> - **`docs/handoff.md`'s P1 item "Settings UI for `dragSnapModifier`/`gridModifier` — still
>   hand-edit `settings.json`" is stale.** Commit `e423244` ("feat: Preferences pane for
>   drag-snap & grid overlay modifiers") shipped it *after* the handoff doc was written, and the
>   current README already documents the Preferences pane. Carried forward here as ✅, not ⬜.
> - **`docs/handoff.md`'s claim `WorkspaceController.recapture is non-atomic` cites a method that
>   no longer exists under that name** — current `WorkspaceController.swift` has
>   `captureCurrent(name:)` (line 33), not `recapture`. Unclear whether the atomicity concern
>   still applies post-rename; carried forward as 🔬 OWED rather than dropped or asserted true.
>
> #### What I deliberately did NOT do, and why
> - Did not edit `docs/design/v1.md`'s Build-order section or the stale code comments above —
>   doc-consolidation's contract is fold-and-stage, not content rewrites of docs that stay in
>   place. Corrected status is tracked here in §4 instead; `docs/design/v1.md` still reads as
>   originally written (its architecture/schema sections are accurate and it's actively
>   referenced from `README.md`, so it stays put, un-edited).
> - Did not touch `docs/release.md` or `docs/appcast.xml` — live Sparkle/notarization deploy
>   contracts, not plans (per this sweep's explicit Mullion carve-out).
> - Did not verify the `ModifierMask` "partial chord coverage" or "iTerm off-by-1px" claims
>   against current source beyond a light grep — carried forward from `docs/handoff.md`
>   unchanged; see §3.
>
> #### Questions
> - None blocking. One verification owed (`captureCurrent` atomicity, see §3).

---

## §1 Post-v1 cleanup queue

Folded from `docs/handoff.md` § "Post-v1 cleanup queue." All still open — none had a fixing
commit in `git log`.

- ⬜ **CLEAN-1** `scripts/release.sh` emits a duplicated `length` attribute in the appcast
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

- ⬜ **DEFER-1** Arrangement match doesn't behaviorally apply `defaultLayoutID` — verified still
  true by reading `AppDelegate.swift:52-58`: `arrangementRegistry.onMatched` logs the matched
  arrangement's default layout name and calls `autoRestoreBoundWorkspaces`, but never applies
  the layout itself. Only the workspace-binding path acts on a match today.
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

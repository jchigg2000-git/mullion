# Mullion — Decisions

Append-only. One entry per ship or per decision that changes direction. **Supersede, never
silently rewrite** — a decision that is later reversed gets a new entry that names and supersedes
the old one; the old entry stays. Roadmap items cite entries by date + title.

This file absorbs `CHOICES.md` (implementation choices made while building v1 that weren't
explicit in the design doc) and the "Don't break (v1 invariants)" list from `docs/handoff.md`,
folded in during the 2026-08-07 doc-consolidation pass. Both source docs are staged to purgatory;
recover via `git show a59ba2f:CHOICES.md` / `git show a59ba2f:docs/handoff.md`.

## (undated, pre-v1.0.0) — Build / toolchain choices

- **Swift 5.10, not Swift 6.** Avoids drowning the v1 build in strict-concurrency errors on first
  compile. Revisit post-v1.
- **XCTest, not Swift Testing.** Compatible with Swift 5.10 + Xcode 15.x; Swift Testing requires
  Swift 6 / Xcode 16.
- **KeyboardShortcuts pinned `from: 2.2.0`.** Maintained Sindre Sorhus library, MASShortcut
  successor.

## (undated, pre-v1.0.0) — Persistence

- **One JSON file per concern** (`layouts.json`, `bindings.json`, `app-rules.json`,
  `window-history.json`, `settings.json`). Atomic write via `FileManager.replaceItem`. Debounce
  handled by `JSONStore` (500ms).
- **`Application Support/Mullion/`** as the data dir, created on first launch.
- **No FSEvents watch in v1** at the time this was written — "Reload Layouts" menu item triggers
  a fresh load. (Superseded: FSEvents auto-reload shipped later — `Persistence/ConfigFileWatcher.swift`,
  Phase C, see `ROADMAP.md` §4.)

## (undated, pre-v1.0.0) — Hotkeys

- **`HotkeyManager` wraps `KeyboardShortcuts`** so the rest of the codebase doesn't import the
  package directly. Keeps the dependency at one boundary.
- **`HotkeyBinding.shortcutName` is a raw `String`**, not a `KeyboardShortcuts.Name`, so it stays
  `Codable` without leaking the package into the data layer.

## (undated, pre-v1.0.0) — Window mutation

- **`AXEnhancedUserInterface` toggle uses the attribute key as a `CFString` literal** — non-public
  but stable since 2015 (yabai, Hammerspoon, every Mac WM uses it).
- **Resize dance: size → position → size.** Matches yabai's `window_manager.c` pattern.

## (undated, pre-v1.0.0) — Sticky focus

- **Independent cycle position per window.** `ActionDispatcher` keys cycle state on
  `(AXUIElement, HotkeyBinding.id)` — pressing left-half twice on Window A doesn't advance
  Window B's cycle.

## (undated, pre-v1.0.0) — Permission revocation

- **Live probe is `CGEvent.tapCreate(.listenOnly)` against `.cgSessionEventTap`.** Created and
  immediately invalidated. If creation returns nil, AX is revoked regardless of what
  `AXIsProcessTrusted` claims.

## (undated, pre-v1.0.0) — Auto-restore

- **Runs once on `applicationDidFinishLaunching`,** not periodically. Re-launching the app is the
  trigger; mid-session app launches are handled by per-app rules at first window appearance
  (deferred to a future step at the time — since resolved by the shipped `AppRule` +
  `LearnedPlacement` resolution path).

## (undated, pre-v1.0.0) — Geometry

- **Origin-zero screen is computed once per geometry call**, not cached. The set of screens can
  change at any notification; safer to look up each time.
- **`Geometry.appKitToAX` returns nil if there is no origin-zero screen.** Caller must handle
  (means no displays — degenerate case).

## (undated, pre-v1.0.0) — Default bindings seeder

- **First-run only**, gated by `UserDefaults.standard.bool(forKey: "Mullion.didSeedDefaultBindings")`.
  Skips if `bindings.json` already has entries.
- Writes both halves of the binding state: the `HotkeyBinding` row in `bindings.json` (data
  layer) AND the actual key combo via `KeyboardShortcuts.setShortcut` (library's `UserDefaults`).
  Without the second call, names exist but no keys fire.
- Defaults ship as `⌃⌥←/→/↑` for halves+maximize and `⌃⌥1-6` for the 6-pane cells — low collision
  risk with system and common app shortcuts.

## (undated, pre-v1.0.0) — Dev workflow gotchas (Sequoia)

- **Launch via `open /Applications/Mullion.app`, not by executing the binary directly from a
  shell.** TCC's "responsible process" model attributes shell-launched binaries to the terminal's
  identity (e.g., iTerm), so `AXIsProcessTrusted()` returns false even after a valid grant.
- **AX grants are invalidated by every rebuild** for ad-hoc-signed dev builds — TCC keys on the
  binary's cdhash. Workflow: `tccutil reset Accessibility com.mullion.Mullion` after each
  rebuild, then re-grant via System Settings. A proper Developer ID signature stabilizes this
  (resolved for release builds once signing/notarization shipped, Phase B).
- **Install location matters.** Grants from `DerivedData/Build/Products/Debug/` paths can be
  flaky on Sequoia. Copy the built `.app` to `/Applications/` and grant from there.

## 2026-05-26 — v1.0.0 shipped; the following are do-not-break invariants

Folded from `docs/handoff.md`'s "Don't break (v1 invariants)" section, written at ship time.

- **Sparkle EdDSA private key** lives in the login keychain (account `ed25519`, "Private key for
  signing Sparkle updates"); backed up in 1Password. **Never run `generate_keys -f` with a
  different key file** — every installed Mullion would be stranded. Public key in
  `Mullion/Resources/Info.plist:SUPublicEDKey` is `oygksZFoPUioT7fCIpjr/WDtdH/3z4CbuPT249aCx3E=`.
- **Feed URL**: `SUFeedURL` is `https://jchigg2000-git.github.io/mullion/appcast.xml`. Pages
  source = `main` / `/docs`. Changing either side requires a coordinated update.
- **Appcast enclosure URL convention**:
  `https://github.com/jchigg2000-git/mullion/releases/download/v<VERSION>/Mullion-<VERSION>.dmg`.
  `scripts/release.sh` bakes this in.
- **`ArrangementRegistry.recompute` only fires `onMatched`/`onUnknown` on transitions** — any
  future caller needing a refire must invoke the callback directly, not call `recompute()` and
  expect it.
- **`WorkspaceController.framesEqualWithinTolerance` uses `< 2`** matching
  `StandardWindowMover`'s success threshold.
- **`Workspace.arrangementID` is optional `Codable` with `decodeIfPresent`.**
- **Multi-display overlay placement requires `setFrame(screen.frame, display: false)` after
  init.**
- **`xcodegen generate` before `xcodebuild`** after adding files under `Mullion/`.
- (Note, added at fold time 2026-08-07): the same section also called
  **`WorkspaceController.recapture` non-atomic** — current source has no method by that name;
  `WorkspaceController.swift:33` has `captureCurrent(name:)` instead. Left as an open question,
  see `ROADMAP.md` §3/§5 — not re-asserted here as still-true, since it may describe a since-
  renamed or since-rewritten code path.

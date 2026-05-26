# Handoff — 2026-05-26 13:45 local

## v1.0.0 shipped

- **Release**: https://github.com/jchigg2000-git/mullion/releases/tag/v1.0.0
- **Tag**: `v1.0.0` (commit `12fea47` — version bump + CHANGELOG.md; appcast item committed in `910b380`).
- **DMG**: `release-build/Mullion-1.0.0.dmg`, 2.79 MB. Signed by `Developer ID Application: Justin Higgins (34RWZN7B74)`, notarized via Apple (submission `6b89a76e-…`), stapled, Sparkle-signed.
- **Appcast**: `docs/appcast.xml` published via Pages at `https://jchigg2000-git.github.io/mullion/appcast.xml`. Item `<title>Mullion 1.0.0</title>`, `pubDate=Tue, 26 May 2026 18:42:25 +0000`.
- **CHANGELOG.md**: created at repo root as the canonical release-notes source for future releases.
- **Gatekeeper pre-flight**: `spctl --assess --type execute` against the mounted `.app` returns `accepted / source=Notarized Developer ID`.

## Don't break (v1 invariants)

- **Sparkle EdDSA private key**: in login keychain (account `ed25519`, "Private key for signing Sparkle updates"); backed up in 1Password. Never run `generate_keys -f` with a different key file — every installed Mullion would be stranded. Public key in `Mullion/Resources/Info.plist:SUPublicEDKey` is `oygksZFoPUioT7fCIpjr/WDtdH/3z4CbuPT249aCx3E=`.
- **Feed URL**: `SUFeedURL` is `https://jchigg2000-git.github.io/mullion/appcast.xml`. Pages source = `main` / `/docs`. Changing either side requires a coordinated update.
- **Appcast enclosure URL convention**: `https://github.com/jchigg2000-git/mullion/releases/download/v<VERSION>/Mullion-<VERSION>.dmg`. The release.sh snippet bakes this in.
- (Carried forward) **`ArrangementRegistry.recompute` only fires `onMatched/onUnknown` on transitions** — any future caller needing a refire must invoke the callback directly, not call recompute() and expect it. **`WorkspaceController.framesEqualWithinTolerance` uses `< 2`** matching `StandardWindowMover` success threshold. **`Workspace.arrangementID` is optional Codable with `decodeIfPresent`**; **`WorkspaceController.recapture` is non-atomic**; **multi-display overlay placement requires `setFrame(screen.frame, display: false)` after init**; **xcodegen generate before xcodebuild** after adding files in `Mullion/`.

## Post-v1 cleanup queue (small)

1. **`scripts/release.sh` emits duplicated `length` attribute in appcast snippet.** Line 192 hardcodes `length="$SIZE_BYTES"`; line 193 pastes `$SPARKLE_SIG_LINE` which already contains `length="..."`. The duplicate was hand-stripped from `docs/appcast.xml` before commit, but the script should drop its own `length=` line. One-line fix.
2. **`scripts/release.sh:83` pipes through `xcpretty` which isn't installed.** Non-fatal — falls through to raw xcodebuild output. `brew install xcpretty` or remove the `| xcpretty || true`.
3. **`.app` is not stapled, only the DMG is.** Gatekeeper does online notarization lookup on first launch after copy from DMG. Works fine, but staple-the-app would make first-launch offline-safe. Means re-ordering scripts/release.sh: notarize → staple the .app → repackage DMG → submit DMG → staple DMG. Or simpler: `xcrun stapler staple` on the .app post-notarize and accept the DMG already contains the unstapled copy.
4. **Demote diagnostic logging to `.debug`.** `autoRestore-entry/skip/bound/fire` in AppDelegate and `restore-begin/end/bundle/item/skip-*` in WorkspaceController are at `.notice` for v1 dogfooding. Once a few real users are on it without surprises, drop to `.debug`.

## Deferred / open (post-v1, by tier)

**P1 (real polish, would-be-nice-soon)**
- **Discord refuses to resize on restore.** Electron min-height enforcement. Candidate fix: a `respect-min-size` `CompatProfile` flag.
- **Finder fullscreen window won't move.** AX-resistant; possibly inherent to fullscreen Spaces.
- **iTerm sidebar off-by-1px** (`dx=-1`). Masked by the `< 2` idempotence guard but rounding lives in `FrameResolver` / `Geometry`.
- **Settings UI for `dragSnapModifier` / `gridModifier`.** Still hand-edit `settings.json`. Sketched and reverted in a prior session; pickup is straightforward.
- **Wallpaper tint doesn't refresh on wallpaper/space change.** Sampled once per display on first overlay show, cached for app lifetime.

**P2 (deferred, intentional)**
- **Phase D follow-up — behavioural application of `defaultLayoutID`.** `onMatched` logs the default layout but doesn't apply it (only the workspace path acts on match).
- **Tests for Phase E overlays + `WorkspaceController` capture/restore.** Only exercised via running app.
- **`WorkspaceController.recapture` non-atomic.**
- **`ModifierMask` chord coverage partial** (`controlOption`, `controlShift`, `optionShift`).
- **`HotkeyBinding.swift:16` `case focus` "v1: stub"** — intentional.
- **`AppRulesEditorView.swift:234` Phase G escape hatch** — intentional.
- **`SystemWindowManager` fallback (step #29, Phase G)** — hold-for-demand.

## Per-release flow (from now on)

```sh
# 1. Bump MARKETING_VERSION in project.yml
# 2. Update CHANGELOG.md with a new ## [x.y.z] section
# 3. Build:
VERSION=x.y.z \
  DEVELOPER_ID_APP="Developer ID Application: Justin Higgins (34RWZN7B74)" \
  NOTARY_KEYCHAIN_PROFILE=mullion-notary \
  make release
# 4. spctl mount-and-assess sanity (see below)
# 5. git commit -am "release: vX.Y.Z" && git tag vX.Y.Z && git push origin main && git push origin vX.Y.Z
# 6. gh release create vX.Y.Z release-build/Mullion-X.Y.Z.dmg --title "Mullion X.Y.Z" --notes-file <changelog-section>.md
# 7. Paste cleaned <item> snippet into docs/appcast.xml, strip the duplicate length="...", commit, push.
```

Verify DMG before publishing:
```sh
MOUNT=$(hdiutil attach -nobrowse -readonly release-build/Mullion-VERSION.dmg | tail -1 | awk -F'\t' '{print $NF}')
spctl --assess --type execute --verbose=4 "$MOUNT/Mullion.app"   # expect: accepted source=Notarized Developer ID
hdiutil detach "$MOUNT" -quiet
```

## How to verify
```
git log --oneline -5
git status
xcodegen generate
xcodebuild -project Mullion.xcodeproj -scheme Mullion -destination 'platform=macOS' test 2>&1 | grep "Executed.*tests" | tail -1
```
Expected: HEAD on `main` at `910b380` or later; clean tree; `Executed 69 tests, with 0 failures`.

To watch update activity:
```
/usr/bin/log stream --predicate 'subsystem == "com.mullion.Mullion" && category == "updater"' --info --style syslog
```

# Implementation Choices Log

Decisions made while building v1 that weren't explicit in the design doc.

## Build / toolchain

- **Swift 5.10, not Swift 6.** Avoids drowning the v1 build in strict-concurrency errors on first compile. Revisit post-v1.
- **XCTest, not Swift Testing.** Compatible with Swift 5.10 + Xcode 15.x. Swift Testing requires Swift 6 / Xcode 16.
- **KeyboardShortcuts pinned `from: 2.2.0`.** Maintained Sindre Sorhus library, MASShortcut successor.

## Persistence

- **One JSON file per concern** (`layouts.json`, `bindings.json`, `app-rules.json`, `window-history.json`, `settings.json`). Atomic write via `FileManager.replaceItem`. Debounce handled by `JSONStore` (500ms).
- **`Application Support/Mullion/`** as the data dir. Created on first launch.
- **No FSEvents watch in v1.** Reload Layouts menu item triggers a fresh load.

## Hotkeys

- **`HotkeyManager` wraps `KeyboardShortcuts`** so the rest of the codebase doesn't import the package. Keeps the dep at one boundary.
- **`HotkeyBinding.shortcutName` is a `String` (raw)**, not a `KeyboardShortcuts.Name`, so it stays Codable without leaking the package into the data layer.

## Window mutation

- **`AXEnhancedUserInterface` toggle uses the attribute key as a `CFString` literal** — non-public but stable since 2015 (yabai, Hammerspoon, every Mac WM uses it).
- **Resize dance: size → position → size.** Matches yabai's `window_manager.c` pattern.

## Sticky focus

- **Independent cycle position per window.** `ActionDispatcher` keys cycle state on `(AXUIElement, HotkeyBinding.id)` — pressing left-half twice on Window A doesn't advance Window B's cycle.

## Permission revocation

- **Live probe is `CGEvent.tapCreate(.listenOnly)` against `.cgSessionEventTap`.** Created and immediately invalidated. If creation returns nil, AX is revoked regardless of what `AXIsProcessTrusted` claims.

## Auto-restore

- **Runs once on `applicationDidFinishLaunching`,** not periodically. Re-launching the app is the trigger; mid-session app launches are handled by per-app rules at first window appearance (deferred to a future step).

## Geometry

- **Origin-zero screen is computed once per geometry call**, not cached. The set of screens can change at any notification; safer to look up each time.
- **`Geometry.appKitToAX` returns nil if there is no origin-zero screen.** Caller must handle (means no displays — degenerate case).

## Default bindings seeder

- **First-run only**, gated by `UserDefaults.standard.bool(forKey: "Mullion.didSeedDefaultBindings")`. Skips if `bindings.json` already has entries.
- Writes both halves of the binding state: the `HotkeyBinding` row in `bindings.json` (data layer) AND the actual key combo via `KeyboardShortcuts.setShortcut` (library's UserDefaults). Without the second call, names exist but no keys fire.
- Defaults ship as `⌃⌥←/→/↑` for halves+maximize and `⌃⌥1-6` for the 6-pane cells. **Why:** these chord prefixes have low collision risk with system and common app shortcuts.

## Dev workflow gotchas (Sequoia)

- **Launch via `open /Applications/Mullion.app`, not by executing the binary directly from a shell.** TCC's "responsible process" model attributes shell-launched binaries to the terminal's identity (e.g., iTerm). The grant on Mullion is correctly recorded but enforced against the terminal, so `AXIsProcessTrusted()` returns false even after a valid grant.
- **AX grants are invalidated by every rebuild** for ad-hoc-signed dev builds — TCC keys on the binary's cdhash. Workflow: `tccutil reset Accessibility com.mullion.Mullion` after each rebuild, then re-add via System Settings. A proper Developer ID signature would stabilize this; deferred until release-engineering work.
- **Install location matters.** Grants from `DerivedData/Build/Products/Debug/` paths can be flaky on Sequoia. Copy the built `.app` to `/Applications/` and grant from there.

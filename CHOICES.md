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

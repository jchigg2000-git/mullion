# Changelog

All notable changes to Mullion are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); Mullion uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-05-26

First public release. Mullion is a window manager for ultrawide and
superwide displays — Rectangle/Magnet/Loop treat a 32:9 or 49" screen
as one big 16:9; Mullion treats it as the wide canvas it actually is.

### Added

- **Zone engine.** User-defined rectangular zones per display, saved
  as named layouts. Layout-level outer margins and inner gap. Snap
  the focused window into a zone by hotkey, with cycling and
  per-zone sticky focus.
- **Ultrawide-first preset layouts.** Asymmetric zones, 6-pane grids,
  1/4-1/2-1/4 splits, center-stage + side rails.
- **SwiftUI layout editor.** Live aspect-correct preview, axis
  presets, fill-gap actions, drag-to-reorder zones, per-zone hotkey
  badges.
- **App rules.** Per-app default zones with learned placements, plus
  a `compatibilityProfile` escape hatch for AX-resistant apps.
- **Drag-to-snap.** Mouse-driven overlay shows zone targets while
  you drag a window; release inside one to snap.
- **Hold-modifier grid overlay.** Press the configured modifier to
  surface the active layout's zones as a wallpaper-tinted overlay.
- **Arrangements.** Multi-display setups are detected as a tuple;
  per-arrangement default layouts switch automatically when you
  plug in or unplug a display.
- **Workspaces.** Named captures of every window's layout + zone
  assignment, restorable on demand or auto-triggered when an
  arrangement becomes active.
- **Auto-update via Sparkle 2.** Signed EdDSA appcast at
  `https://jchigg2000-git.github.io/mullion/appcast.xml`. Manual
  check from the menu bar.
- **Onboarding.** Accessibility permission is requested on first
  launch and re-surfaced if a hotkey fires without trust.

### Known limitations

- A handful of apps with hard min-size constraints (Discord and
  similar Electron apps, Finder in fullscreen Spaces) silently
  ignore AX resize requests. The mover reports success because the
  AX call returned, but the window snaps back to its enforced size.
- Settings UI for the drag-snap / grid-overlay modifier keys is
  pending; for now edit `~/Library/Application Support/Mullion/settings.json`
  directly.
- Wallpaper tint for the grid overlay is sampled once per display
  on first show and cached; changing wallpaper requires an app
  restart to refresh.

[1.0.0]: https://github.com/jchigg2000-git/mullion/releases/tag/v1.0.0

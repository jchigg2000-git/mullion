# Mullion

A macOS window manager built for ultrawide and superwide monitors.

Tools like Rectangle, Magnet, and Loop were designed for 16:9 displays and
multi-monitor setups. They treat a 32:9 or 49" superwide as one big screen
with halves and thirds. Mullion is the opposite: it assumes your display is
wide and ships layouts, zones, and per-app rules that actually use the
space — asymmetric zones, 6-pane grids, 1/4-1/2-1/4 splits, and
center-stage-plus-side-rails configurations.

> **Status:** beta. The core engine (zone snapping, hotkey cycling, per-app
> rules, learned placements, auto-restore, SwiftUI layout editor) is shipped.
> See [docs/design/v1.md](docs/design/v1.md) for the full scope and the
> remaining build order. Auto-updates via Sparkle once a public release is
> cut — see [docs/release.md](docs/release.md).

## Why

macOS exposes an ultrawide as a single `NSScreen`. There's no native way to
make it behave like two or three monitors (PbP requires two physical inputs;
virtual-display tools are unreliable). Mullion provides its own zone system
that *feels* like a multi-monitor setup — sticky per-zone focus, per-app
default zones, hotkey snapping, optional gaps, and layouts beyond halves
and thirds.

## v1 scope

- **Zone engine** — user-defined rectangular zones per display, saved as
  named layouts. Layout-level outer margins + inner gap.
- **Global hotkeys** to snap the focused window to a named zone, with
  cycling and per-zone sticky focus.
- **Menu-bar app** with a layout picker and a SwiftUI layout editor with
  live aspect-correct preview.
- **Ultrawide-first presets** — asymmetric zones, 6-pane, 1/4-1/2-1/4,
  center-stage + side rails.
- **Multi-display aware** — handles laptop + ultrawide combos cleanly.
  Arrangement-as-unit configs and per-arrangement default layouts.
- **Workspaces** — named tuples of layout + per-app placements,
  optionally arrangement-triggered.
- **Mouse-driven UX** — drag-to-snap preview overlay and
  hold-modifier-to-show-grid overlay.
- **Per-app rules** with a `compatibilityProfile` escape hatch for
  AX-resistant apps; explicit fallback to Sequoia's `SystemWindowManager`.
- **Permissions flow** — Accessibility prompt handled cleanly on first
  launch, re-surfaces if a hotkey fires without trust.
- **Updates** — Sparkle 2 with EdDSA-signed appcast.

Out of scope: automatic tiling (yabai-style), Stage Manager integration,
cloud sync, per-Space layouts.

## Building

Requires Xcode 16+ and macOS 15+ (Sequoia).

The Xcode project is generated from `project.yml` via
[XcodeGen](https://github.com/yonaskolb/XcodeGen) so the repo stays free of
binary `.pbxproj` diffs.

```sh
git clone https://github.com/jchigg2000-git/mullion.git
cd mullion
brew install xcodegen     # one-time
xcodegen generate
open Mullion.xcodeproj
```

First launch will prompt for Accessibility. Grant in System Settings →
Privacy & Security → Accessibility; Mullion detects the change automatically.

User-editable configuration lives in `~/Library/Application Support/Mullion/`:
`layouts.json`, `bindings.json`, `app-rules.json`, `window-history.json`,
`settings.json`. Pick "Reload Layouts" from the menu-bar item after editing.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Contributions use a DCO sign-off
(`git commit -s`) — no CLA, no forms.

## Credits

Mullion's design draws on lessons from several excellent open-source macOS
window managers. See [NOTICE](NOTICE) for the full list. Particular thanks
to **Rectangle** and **Loop**, whose source code was invaluable reading
while designing Mullion's zone engine and hotkey handling.

## License

[MIT](LICENSE).

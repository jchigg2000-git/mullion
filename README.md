# Mullion

A macOS window manager built for ultrawide and superwide monitors.

Tools like Rectangle, Magnet, and Loop were designed for 16:9 displays and
multi-monitor setups. They treat a 32:9 or 49" superwide as one big screen
with halves and thirds. Mullion is the opposite: it assumes your display is
wide and ships layouts, zones, and per-app rules that actually use the
space — asymmetric zones, 6-pane grids, 1/4-1/2-1/4 splits, and
center-stage-plus-side-rails configurations.

> ⚠️ **Status:** early development. Not yet ready for daily use.

## Why

macOS exposes an ultrawide as a single `NSScreen`. There's no native way to
make it behave like two or three monitors (PbP requires two physical inputs;
virtual-display tools are unreliable). Mullion provides its own zone system
that *feels* like a multi-monitor setup — sticky per-zone focus, per-app
default zones, hotkey snapping, optional gaps, and layouts beyond halves
and thirds.

## Planned v1 scope

- **Zone engine** — user-defined rectangular zones per display, saved as
  named layouts
- **Global hotkeys** to snap the focused window to a named zone
- **Menu-bar app** with a layout picker
- **Ultrawide-first presets** — asymmetric zones, 6-pane, 1/4-1/2-1/4,
  center-stage + side rails
- **Multi-display aware** — handles laptop + ultrawide combos cleanly
- **Permissions flow** — Accessibility prompt handled cleanly on first launch

Out of scope for v1: automatic tiling (yabai-style), workspaces, Stage
Manager integration, drag-to-snap preview UI.

## Building

Requires Xcode 15+ and macOS 13+.

```sh
git clone https://github.com/jchigg2000-git/mullion.git
cd mullion
open Mullion.xcodeproj
```

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

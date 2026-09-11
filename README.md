# Mullion

A macOS window manager built for ultrawide and superwide monitors.

Tools like Rectangle, Magnet, and Loop were designed for 16:9 displays and
multi-monitor setups. They treat a 32:9 or 49" superwide as one big screen
with halves and thirds. Mullion is the opposite: it assumes your display is
wide and ships layouts, zones, and per-app rules that actually use the
space — asymmetric zones, 6-pane grids, 1/4-1/2-1/4 splits, and
center-stage-plus-side-rails configurations.

## Install

```bash
brew install --cask jchigg2000-git/tap/mullion
```

Homebrew now gates third-party taps, so the first install asks you to trust
the tap — `brew trust jchigg2000-git/tap` — before it will resolve.

Or download [Mullion-1.0.0.dmg](https://github.com/jchigg2000-git/mullion/releases/latest)
directly. Builds are signed and notarized with a Developer ID, and update
themselves via Sparkle. Requires macOS 15 or later.

> **Status:** beta. The core engine (zone snapping, hotkey cycling, per-app
> rules, learned placements, auto-restore, SwiftUI layout editor) is shipped;
> [v1.0.0](https://github.com/jchigg2000-git/mullion/releases/tag/v1.0.0) is
> out with signed, notarized, Sparkle auto-updating builds. See
> [docs/design/v1.md](docs/design/v1.md) for the full scope and remaining
> build order, [CHANGELOG.md](CHANGELOG.md) for release notes, and
> [docs/release.md](docs/release.md) for how releases are cut.

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

## Stack

- **Swift** (5.10 toolchain, macOS 15+ deployment target) with **SwiftUI**
  for the layout editor and settings UI, and AppKit + the Accessibility
  (AX) APIs for the menu-bar item and window placement.
- **[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)**
  for global hotkey capture and
  **[Sparkle 2](https://github.com/sparkle-project/Sparkle)** for signed
  auto-updates, both pulled in via Swift Package Manager.
- No backend and no runtime network calls beyond Sparkle's update check;
  all state is local JSON under `~/Library/Application Support/Mullion/`.

## Building

Requires Xcode 16+ and macOS 15+ (Sequoia).

Prebuilt, signed, and notarized DMGs are published on the
[Releases page](https://github.com/jchigg2000-git/mullion/releases) for
tagged versions (starting at v1.0.0); installed copies auto-update via
Sparkle. To build from source instead:

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

Build and run from Xcode (⌘R). Mullion is menu-bar-only (`LSUIElement`) —
no Dock icon or window; look for its icon in the menu bar after launch.

First launch will prompt for Accessibility. Grant in System Settings →
Privacy & Security → Accessibility; Mullion detects the change automatically.

### Tests

```sh
xcodegen generate
xcodebuild -project Mullion.xcodeproj -scheme Mullion \
  -destination 'platform=macOS' test
```

User-editable configuration lives in `~/Library/Application Support/Mullion/`:
`layouts.json`, `bindings.json`, `app-rules.json`, `window-history.json`,
`settings.json`. Pick "Reload Layouts" from the menu-bar item after editing.
Drag-snap and grid-overlay modifier keys, and auto-restore, are also
editable from the layout editor's Preferences pane.

## Project layout

```
Mullion/
  Core/         AppDelegate, menu-bar status item
  Display/      Display + arrangement (multi-monitor) detection
  Layout/       Zones, layouts, workspaces — data model + controllers
  Hotkeys/      Global hotkey bindings + dispatch
  Rules/        Per-app default zones, learned placements
  Window/       Accessibility-API window reads/moves
  Overlay/      Drag-to-snap + hold-modifier grid overlay UI
  Permissions/  Accessibility permission gate
  Persistence/  JSON store + config file watching
  Settings/     App settings model + store
  UI/           SwiftUI editors (layout, bindings, app rules, workspaces)
  Update/       Sparkle updater controller
  Compat/       Per-app compatibility profiles / escape hatches
MullionTests/   Unit tests, mirroring the source layout above
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

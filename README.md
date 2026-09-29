# gamma-control

Interactive gamma curve editor for macOS. Drag control points on an RGB curve
and your display responds live - lift shadows for dark rooms, add contrast,
go full night-vision green if that is your thing. Quit the app and everything
restores to normal.

```sh
cd macos
open curves.command        # or double-click it in Finder
```

First run compiles the Swift source (needs Xcode Command Line Tools:
`xcode-select --install`); later runs start instantly and only recompile when
the source changes.

## Features

- **Click** the curve to add a control point, **drag** to move it,
  **right-click** (or ctrl-click) to remove
- Per-channel editing: RGB / R / G / B tabs
- Contrast and brightness sliders, applied on top of your curve
- **Presets**: Default, S-Curve, Shadow Lift, Night Vision, High Contrast,
  Crisp, Soft, See Dark lite, See Dark, Cave Games - and the preset list is
  plain Swift at the top of `curves.swift`, edit freely
- Multi-monitor: pick the target display from the dropdown
- Animated transitions between curve changes
- **Auto** mode samples screen brightness once a second and gently shifts
  brightness to hold a steady perceived level (macOS will ask for Screen
  Recording permission the first time; the 64x36 sample never leaves your
  machine)

## How it works

The editor builds a 256-entry RGB transfer table from your control points and
applies it with `CGSetDisplayTransferByTable`. Nothing is installed, nothing
runs in the background, and quitting the app restores your normal gamma
(`CGDisplayRestoreColorSyncSettings`). macOS also resets gamma on resolution
or ColorSync changes, so a reboot or display change always returns you to
stock.

## Notes

- The gamma table applies to the whole display, not per-app.
- Night Shift / True Tone compose on top of your curve.

## License

MIT. Not affiliated with Apple.

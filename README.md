# gamma-control

Cross-platform display gamma tools: an interactive RGB curve editor for macOS
and a quick terminal gamma booster for macOS and Windows.

Want your games or terminal readable in a dark room without washing everything
out? Set a curve once, tweak live, and everything restores to normal when you
close the app.

## macOS: Gamma Curves (GUI)

```sh
cd macos
open curves.command        # or double-click it in Finder
```

First run compiles the Swift source (needs Xcode Command Line Tools:
`xcode-select --install`); later runs start instantly and only recompile when
the source changes.

- **Click** the curve to add a control point, **drag** to move it,
  **right-click** (or ctrl-click) to remove
- Per-channel editing: RGB / R / G / B tabs
- Contrast and brightness sliders, applied on top of your curve
- **Presets**: Default, S-Curve, Shadow Lift, Night Vision, High Contrast,
  Crisp, Soft, See Dark lite, See Dark, Cave Games - and the preset list is
  plain Swift at the top of `curves.swift`, edit freely
- Multi-monitor: pick the target display from the dropdown
- **Auto** mode samples screen brightness once a second and gently shifts
  brightness to hold a steady perceived level (macOS will ask for Screen
  Recording permission the first time; the 64x36 sample never leaves your
  machine)

## macOS: Gamma Boost (terminal)

```sh
cd macos
open gamma_control.command
```

Applies a flat gamma (default 0.45, lower = brighter shadows). Type a number
(0-1), `d` for default, `q` to quit and restore.

## Windows: Gamma Boost (terminal)

Double-click `windows/gamma_boost.bat`, or:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows/gamma_boost.ps1
```

Type a number (0-1), `d` for default boost (0.45), `r` to reset to normal
(1.0), `q` to quit (restores first).

If extreme values fail silently, Windows is clamping the gamma range. One
time admin fix:

```bat
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM" /v GdiIcmGammaRange /t REG_DWORD /d 0 /f
```

## How it works

Everything uses the OS display-transfer APIs: `CGSetDisplayTransferByTable` /
`CGDisplayRestoreColorSyncSettings` on macOS, `SetDeviceGammaRamp` on Windows.
Nothing is installed, nothing runs in the background, and closing the app
restores your normal gamma (`CGDisplayRestoreColorSyncSettings` / gamma 1.0).
macOS also resets gamma on resolution or ColorSync changes, so a reboot or
display change always returns you to stock.

## Notes

- The gamma table applies to the whole display, not per-app.
- Night Shift / True Tone compose on top of your curve.
- On Windows, some GPU driver panels (and fullscreen exclusive-mode games)
  can override the ramp.

## License

MIT. Not affiliated with Apple or Microsoft.

# Nabz

**Nabz** (نبض, "pulse") is a native macOS app that connects to a Bluetooth heart-rate monitor (primary target: **Polar H10**) and shows your live heartbeat — a beat-synced animation, a large BPM readout, a rolling trend, and heart-rate-zone coloring.

The first release is a polished terminal (TUI) experience; a SwiftUI app and a desktop menu-bar/floating readout follow in later phases, all sharing one UI-agnostic core (`NabzCore`).

See [Nabz-PRD.md](./Nabz-PRD.md) for the full product requirements.

## UI Preview

> ⚠️ **Prototype only.** The images below are early design mockups to convey the intended look and feel. They are **not** the final UI and do not reflect the shipping product. They contain known inconsistencies (zone labels, zone math, the "widget" framing) — PRD **§7b Design Language** is canonical and supersedes them.

### Terminal (Phase 1)

![Terminal prototype](./mockup/terminal.jpg)

### Desktop app (Phase 2)

![Desktop app prototype](./mockup/desktop.jpg)

### Floating desktop readout (Phase 3)

![Floating readout prototype](./mockup/widget.jpg)

*(Rendered as a floating always-on-top panel + menu-bar item — not a WidgetKit widget; see PRD R-5.)*

## Requirements

- macOS 13 or newer.
- A Swift 6 toolchain (Xcode 16+ or the Swift command-line tools).
- For live use: a BLE heart-rate sensor (Polar H10 is the primary target; any sensor advertising the standard Heart Rate Service works). No hardware is needed for `--simulate`.

## Install

```bash
git clone https://github.com/Kaaveh/nabz.git
cd nabz
./install.sh
nabz --simulate    # watch a fake heart beat — no strap required
```

`install.sh` builds a release binary, wraps it in a minimal `Nabz.app` bundle, and symlinks `nabz` onto your `PATH`. The bundle exists for one reason: so the macOS Bluetooth permission prompt is attributed to **Nabz** rather than to your terminal (see [Bluetooth permission](#bluetooth-permission) below).

Defaults are `/Applications/Nabz.app` and `/usr/local/bin/nabz` (the script uses `sudo` only if those aren't writable). Override either:

```bash
APP_DIR=~/Applications BIN_DIR=~/.local/bin ./install.sh
```

The `PATH` symlink points *inside* the bundle, so `nabz` on your `PATH` runs the exact binary the app carries — and inherits the app's Bluetooth-permission identity.

## Quickstart

```bash
nabz                      # scan, connect to your preferred sensor, run the live UI
nabz --list               # list discoverable HR sensors and exit
nabz --device "Polar H10 12345678"
nabz --simulate           # run with a fake heart-rate source (no hardware)
nabz --max-hr 190         # set HRmax for zone calculation
nabz --no-color           # disable coloring (256-color terminals also auto-degrade)
nabz --verbose            # mirror diagnostics to stderr
```

Press `q` (or `Ctrl-C`) to quit — the terminal is always restored cleanly. Your last-used sensor and settings are remembered in `~/.config/nabz/config.json`.

### The `--simulate` demo

`nabz --simulate` runs the full UI against a synthetic heart with plausible BPM drift and RR-intervals. It's the fastest way to see the beating heart, zone colors, and sparkline, and it's the standard development loop — everything except the actual radio behaves exactly as it does live.

## Bluetooth permission

macOS gates Bluetooth behind a TCC permission prompt, and it attributes that prompt to whichever process owns an `Info.plist`. There are two ways to run Nabz, and they grant permission differently (PRD D-01 / R-1):

1. **Installed app bundle (recommended).** After `./install.sh`, running `nabz` executes the binary from inside `Nabz.app`, so the first launch prompts for Bluetooth **as Nabz**, with Nabz's own description. Approve it once and you're set. Manage it later under **System Settings → Privacy & Security → Bluetooth**.

2. **Raw `swift run` (development).** A bare `swift run nabz` has no bundle, so macOS attributes the request to whatever launched it — Terminal, iTerm, or your editor (e.g. Cursor running LLDB). You grant Bluetooth to *that* app once under **System Settings → Privacy & Security → Bluetooth**. This is convenient while iterating but means the permission belongs to your terminal, not to Nabz.

## Troubleshooting

- **`Bluetooth permission denied — grant it in System Settings › Privacy & Security › Bluetooth`** (`unauthorized`). Open that pane and enable the entry for **Nabz** (installed app) or for your terminal/editor (raw `swift run`). If Nabz never appears there, launch it once so it can request access. See [Bluetooth permission](#bluetooth-permission).
- **`Bluetooth is off — turn it on in Control Center or System Settings`** (`bluetoothOff`). Turn Bluetooth on; Nabz reconnects on its own once it's back.
- **No sensor found / won't connect.** Make sure the strap is worn (H10 straps only advertise with skin contact) and isn't already connected to another app or process — only one central can hold the sensor at a time. `nabz --list` shows what's discoverable.
- **Colors look wrong.** Truecolor isn't universal; Nabz falls back to 256-color automatically, and `--no-color` disables coloring entirely.

## Status

Phase 1 (terminal) — see [Nabz-PRD.md](./Nabz-PRD.md) for scope and decisions, [ROADMAP.md](./ROADMAP.md) for the execution order, and [specs/](./specs/) for the Phase-1 spec set.

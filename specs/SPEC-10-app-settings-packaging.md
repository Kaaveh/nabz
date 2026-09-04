# SPEC-10 — Sidebar, Settings, devices & packaging

## Goal
The rest of the app and its distribution: Dashboard + Settings navigation, HRmax/zone/device preferences shared with the CLI's config file, in-app device discovery and switching, the two-executable `Nabz.app`, the installer, and the README. Closes Phase 2.

## References
PRD §7a, §7b (errata: Dashboard + Settings only), §7.1 (FR-1.2…1.4), §7.4 (FR-4.1…4.3), §10 (R-1, R-6, R-7), D-02, D-08, D-11, D-15, D-16, NFR-4, NFR-5.

## Scope
- **Core lifecycle (D-16):** `stop()` on `HeartRateSource`, implemented by both sources. `BLEHeartRateSource.stop()` cancels any reconnect, unsubscribes, disconnects, and finishes both streams; a new `.stopped` `BLEEvent` takes any state to `.idle` in the pure state machine. `SimulatedHeartRateSource.stop()` cancels the pump. This is the one core change in the spec, bounded to lifecycle.
- **Navigation:** `NavigationSplitView` with sidebar Dashboard / Settings — no History or Trends (§7b errata). The toolbar hosts the SPEC-09 status pill and a Rescan action, enabled when not live. A `Settings` scene (⌘,) shows the same Settings view.
- **Settings:** HRmax explicit value; age with the Tanaka auto-fill shown (D-02); the resolution in effect surfaced in words ("using 190 — placeholder"); five ascending zone thresholds with a live BPM-range preview, validation mirroring `Config.thresholds` (FR-4.1…4.3); preferred device (name, Forget); a session-only "Simulated sensor (demo)" toggle, never persisted because the config file is shared with the CLI. Everything persists through `NabzCore.Config` to `~/.config/nabz/config.json` (D-08), re-read on app activation so CLI edits show up. Changes apply live: zones recolor, and a device change restarts the source via `stop()` + a new instance.
- **Device discovery (FR-1.2, FR-1.3):** Scan runs `BLEHeartRateSource.discover()` and lists name, identifier, RSSI; picking one makes it preferred and reconnects. Settings copy carries the R-6 note: don't run `nabz` and the app at the same time.
- **Packaging (D-15):** `packaging/Info.plist` → `CFBundleExecutable nabz-app`, `LSMinimumSystemVersion 26.0`, `NSBluetoothAlwaysUsageDescription` kept, `LSApplicationCategoryType` healthcare-fitness, `NSHighResolutionCapable`. `install.sh` builds both products in release and copies `nabz-app` and `nabz` into `Contents/MacOS/`; the PATH symlink is unchanged. Placeholder app icon: a heart glyph rendered to `.icns` by a script under `packaging/`; real artwork is out of scope.
- **README:** app section (install, launch, `--simulate` via `open -a Nabz --args --simulate` and `swift run nabz-app --simulate`), Settings walkthrough, requirements split (CLI macOS 13+, app macOS 26+), the R-6 note, Status → Phase 2.

## Non-goals
Code signing / notarization, App Store, App-Store-name and domain checks (R-7 stays deferred per D-11). Phase 3 (`MenuBarExtra`, `NSPanel`). HRV, History, Trends. An in-app appearance override.

## Acceptance criteria
- A newcomer goes from `git clone` to a beating heart in the app using only the README.
- App and CLI read and write the same preferences: change HRmax in one, see it in the other.
- On hardware: switching devices in Settings releases the old central and streams from the new sensor — no zombie connection, no second central holding the strap (R-6).
- Fresh-TCC test (`tccutil` reset): both `Nabz.app` and the symlinked `nabz` prompt for Bluetooth as **Nabz** and then connect. If the CLI's attribution fails, ship the `nabz-cli.app` shim fallback named in D-15 and record it.
- `LSMinimumSystemVersion` blocks the app on macOS < 26 while `nabz` still runs from the symlink.
- Phase-2 exit checklist (ROADMAP) fully green — this spec closes the phase.

## Test plan
Unit: `.stopped` in the transition table; `stop()` finishes both streams on the simulator and cancels the reconnect task on the BLE actor; Settings ↔ `Config` round-trip including malformed thresholds; HRmax resolution display strings. Manual: hardware device switch, the TCC reset walk-through, install on a clean checkout, README dry-run followed literally. CI unchanged (build, tests, both smoke runs).

## Dependencies
SPEC-09 (the dashboard these surfaces wrap); SPEC-03's `BLEEvent` seam for the `stop()` tests.

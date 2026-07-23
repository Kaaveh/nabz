# SPEC-07 — Packaging

## Goal
A clean distributable: the CLI wrapped in a minimal `.app` bundle carrying `NSBluetoothAlwaysUsageDescription`, an install script, and a README that walks through the Bluetooth permission story.

## References
PRD §10 (R-1, R-7), D-01, §11.

## Scope
- Minimal `.app` bundle wrapping the `nabz` binary with an `Info.plist` including `NSBluetoothAlwaysUsageDescription`, so the TCC prompt attributes to Nabz rather than the terminal (R-1).
- Install script: build release, assemble the bundle, place the CLI on `$PATH` (symlink or copy).
- README rewrite for users: install steps, the two permission paths (bundled app vs. raw `swift run` granting Terminal/IDE Bluetooth access per D-01), quickstart, `--simulate` demo, troubleshooting (`unauthorized`, `bluetoothOff`).
- Name-collision check recorded: `nabz` binary name and repo/domain availability (R-7) — verify and note results.

## Non-goals
Code signing / notarization for distribution beyond the owner's machine (revisit if the project goes public). App Store anything. Phase-2 app packaging.

## Acceptance criteria
- Fresh machine-state test (TCC reset via `tccutil` or a clean user): launching the bundled app prompts for Bluetooth with the Nabz name and description, then connects.
- `nabz` on `$PATH` runs the same binary the bundle carries.
- A newcomer can go from `git clone` to a beating heart using only the README.
- Phase-1 exit checklist (§11) fully green — this spec closes the phase.

## Test plan
Manual: the fresh-permission walk-through, install script on a clean checkout, README dry-run followed literally. CI unchanged (build/test/smoke still green).

## Dependencies
SPEC-06 (complete CLI).

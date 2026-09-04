# SPEC-08 — App scaffolding & view model

## Goal
The Phase-2 shell on the simulated source: SPM targets for the SwiftUI app, the macOS 26 gate, an `@Observable` session model fed by the core streams, a placeholder window showing live state and BPM, and CI on Xcode 26. No glass and no hero yet — this spec is about the boundary and the plumbing, the way SPEC-04 was about never breaking the terminal.

## References
PRD §4, §5 (Phase 2), §6, §7a (FR-2A.5), §9, D-08, D-09, D-12, D-13, D-14, NFR-1, NFR-3, NFR-6, NFR-7.

## Scope
- **Boundary fix first (D-13):** move `HeartAnimation`, `HeartFrame`, `beatContraction`, and `DisplayState` from `NabzTUI` into `NabzCore` and make them public; move `HeartAnimationTests` to `NabzCoreTests`. The `NabzTUI` diff is imports only, and `swift test` is green before any app file exists.
- **Targets (D-12):** `NabzApp` library (views + view model, depends on `NabzCore` only), `nabz-app` executable (a thin `@main`), `NabzAppTests`. The whole `NabzApp` module is `@available(macOS 26, *)`; the package floor stays macOS 13 for the TUI.
- **Entry point (D-14):** a plain `@main` type whose `static func main()` checks `#available(macOS 26, *)` and runs the SwiftUI `App`; otherwise it shows an alert naming the requirement and exits non-zero. An `NSApplicationDelegateAdaptor` sets the `.regular` activation policy and activates, so a bundle-less `swift run nabz-app` still fronts a window.
- **Launch arguments:** `--simulate` selects `SimulatedHeartRateSource` (FR-5.1, same spelling as the CLI); otherwise `BLEHeartRateSource(target: config.preferredDevice)` with `Config.loadOrDefault()` (D-08). `--verbose` sets `nabzVerbose` (NFR-7).
- **`HeartRateSession`** (`@MainActor @Observable final class`): owns the source; two ingest tasks (samples, connection state) exactly as `runTUI` does; exposes `connectionState`, `latestSample`, `displayState` (core `DisplayState`), `sensorName`, `elapsed`, `hrMax`, `thresholds`. `frame(now:)` ingests a new sample once (de-duped by timestamp), advances the core `HeartAnimation`, and returns its `HeartFrame`. No timers in the model — SPEC-09 drives time from the view with `TimelineView`. Saves the preferred device on `.connected` via `Config.save` (FR-1.4), as `Nabz.swift` does today.
- **Placeholder window:** one `WindowGroup` with a minimum size showing connection state text, sensor name, raw BPM, and a "Simulated" badge — plain SwiftUI, no styling.
- **Latency log:** sample timestamp → ingest delta via `nabzLog` at debug level (NFR-1), mirroring the TUI.
- **`NABZ_SMOKE_SECONDS=N`:** the app runs N seconds then exits 0 — the app-side equivalent of D-10's frame hook, for CI.
- **CI:** runner `macos-26` with Xcode 26.x selected — the toolchain pin from SPEC-01 moves here for all targets. `swift build` now covers every target; `swift test`; the existing TUI smoke run unchanged; new step `NABZ_SMOKE_SECONDS=3 swift run nabz-app --simulate`. If the `macos-26` image is unavailable, use `macos-15` with Xcode 26 selected and record that the runtime-gated `NabzAppTests` skip there.
- `Makefile` gains `run-app`; the `CLAUDE.md` command list is updated.

## Non-goals
Liquid Glass, the heart, sparkline, zone colors (SPEC-09). Sidebar, Settings, device switching, bundle/installer changes (SPEC-10). Any `NabzCore` change beyond the D-13 move.

## Acceptance criteria
- `swift run nabz-app --simulate` opens a window that tracks simulated BPM and connection state live.
- On macOS < 26 (or with the guard forced in a test build) the app shows the refusal message and exits; it never reaches a view.
- `swift test` green, including the moved animation tests and the new session-model tests; `nabz --simulate` is visually unchanged after the move (D-13 is import-only for the TUI).
- CI green on Xcode 26 with both smoke runs.

## Test plan
Unit (`NabzAppTests`, a scripted fake `HeartRateSource` with hand-fed continuations): each sample ingested exactly once across repeated `frame(now:)` calls; `displayState` follows state + contact through the §7b table; preferred device saved on `.connected` under a temp `HOME`; `--simulate` / `--verbose` argument parsing. Manual: window fronting from `swift run`; the refusal path. CI: as above.

## Dependencies
SPEC-07 (Phase 1 complete).

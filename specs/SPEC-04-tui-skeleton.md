# SPEC-04 — TUI renderer skeleton

## Goal
A robust full-screen terminal shell: raw mode, alternate buffer, a steady render loop, resize handling, and state-driven layout — running against the simulated source. No heart animation yet; this spec is about never breaking the terminal.

## References
PRD §7.3 (FR-3.5…3.7), §7b (layout, state visuals), §8 (NFR-2, NFR-3, NFR-4, NFR-7), FR-1.7, D-04.

## Scope
- Hand-rolled ANSI renderer (D-04): raw mode, alternate screen buffer, cursor hidden, diff-based redraws where practical (NFR-2).
- Render loop at a steady cadence (30–60 fps target) without busy-spinning (NFR-3).
- Single teardown path restoring the terminal from every exit: SIGINT, SIGTERM, normal quit, and (best-effort) crash (FR-1.7, NFR-4).
- SIGWINCH → relayout; §7b degradation order when below 80×24 (drop legend → drop sparkline → heart + BPM only).
- State-driven layout per §7b state-visuals table: scanning, connecting, live (placeholder content), no contact, reconnecting, error/unauthorized/bluetoothOff — each visually distinct (FR-3.6) with actionable copy for the permission states (R-1).
- Status line: connection state, sensor name, contact indicator, elapsed time, active HRmax (FR-3.5, D-02).
- Truecolor with 256-color fallback, detected via `$COLORTERM`; `--no-color` styling path renders textual state (FR-3.7, R-4; the flag wiring is SPEC-06).
- Runs against `SimulatedHeartRateSource` — this spec needs no hardware.

## Non-goals
The beating heart, sparkline, and zone coloring (SPEC-05). BLE (SPEC-03). CLI flags (SPEC-06).

## Acceptance criteria
- Start → quit (Ctrl-C, SIGTERM, or `q`) always returns a pristine terminal, including when killed mid-redraw.
- Resizing the terminal live never corrupts the layout; degradation order matches §7b.
- Every `ConnectionState` renders its distinct visual, driven by scripting the simulated source through states.
- CPU stays idle-to-light while running (NFR-3, spot-check via Activity Monitor).

## Test plan
Unit: layout math (breakpoints, degradation order) and ANSI diffing logic. Manual: resize torture, kill -TERM mid-run, run in a 256-color terminal and with `TERM=dumb`-ish fallback. CI: `--simulate` smoke run (launch, render N frames, clean exit) — this becomes the NFR-6 smoke test.

## Dependencies
SPEC-01 (simulated source, models).

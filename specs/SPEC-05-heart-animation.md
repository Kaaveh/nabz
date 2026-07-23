# SPEC-05 — Beating-heart animation

## Goal
The hero. The dot-matrix heart that visibly contracts on each real beat, the eased BPM number, zone coloring, and the rolling sparkline — tuned entirely in `--simulate`.

## References
PRD §1 ("the heartbeat is the product"), §7.3 (FR-3.1…3.4), §7.4 (incl. FR-4.4), §7b (brand, palette, motion), D-02, D-03, D-07, R-3, NFR-1, NFR-2.

## Scope
- **Beating heart (FR-3.1):** dot-matrix/braille heart per §7b brand; beats scheduled from RR-intervals, BPM-derived cadence fallback when RR is absent (R-3). Motion per §7b: ~120 ms systole contraction, eased diastole release until the next scheduled beat.
- **Honest idle:** scanning/reconnecting shows the dimmed fixed-cadence idle pulse (§7b) — never a fake live beat.
- **BPM number (FR-3.2):** block-glyph digits, ~300 ms ease-out tween toward each new sample (D-03) — a tween on the displayed number, not a moving average.
- **Zone coloring (FR-3.4):** heart + BPM colored by active zone from the §7b palette, including the neutral below-zones treatment (FR-4.4, D-07); active zone highlighted in the legend and named in the status line (accessibility, §7b).
- **Sparkline (FR-3.3):** 60 s rolling window of raw BPM samples (D-03), block/braille glyphs, zone-colored per sample.
- Truecolor + 256-color palette values per §7b table.
- Latency instrumentation: simulated-sample timestamp → render timestamp delta logged, for the §11 exit-checklist measurement (NFR-1).

## Non-goals
Real BLE data (works via SPEC-03 with zero changes here, by construction). Config for window length/HRmax (SPEC-06 wires flags; this spec reads values from core defaults).

## Acceptance criteria
- In `--simulate`, the heart visibly beats in time with the simulated RR-intervals; cutting RR data from the simulator switches to BPM-derived cadence without a visual break.
- BPM changes glide (no snapping); sparkline scrolls; zone transitions recolor heart, number, and legend consistently.
- Below-zone BPM renders neutral, never Z1 (FR-4.4).
- Measured sample→render latency < 1 s (NFR-1).
- Frame cadence steady, no flicker or tearing over a 45-minute simulated session (NFR-2).

## Test plan
Unit: beat scheduler (RR present/absent/irregular), BPM tween math, sparkline windowing, zone→color mapping incl. below-zone. Manual: extended `--simulate` viewing sessions — this feature's bar is explicitly qualitative (§11), so tuning time is part of the spec.

## Dependencies
SPEC-04 (renderer shell).

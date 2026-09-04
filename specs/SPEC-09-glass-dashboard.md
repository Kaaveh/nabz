# SPEC-09 — Glass dashboard: the hero heart card

## Goal
The hero, in the app: a Liquid Glass card with the gradient heart beating on the shared scheduler, the eased BPM number, zone coloring that reads in dark and light, the rolling sparkline, the zone legend, and every §7b state visual. Tuned entirely in `--simulate`.

## References
PRD §1 ("the heartbeat is the product"), §7a (FR-2A.1…2A.4), §7b (brand, palette, motion, state visuals, accessibility, errata), §7.3 (FR-3.1…3.6 as the behavioral baseline), §7.4 (FR-4.4), D-02, D-03, D-06, D-07, D-12, D-13, NFR-1, NFR-2, NFR-3.

## Scope
- **Glass surfaces (FR-2A.1):** a `GlassEffectContainer` grouping the hero card, the status pill, and the zone legend, each with `.glassEffect()`; `glassEffectID(_:in:)` on the heart so live ↔ idle ↔ alert morph instead of cut (FR-2A.4). Standard SwiftUI controls everywhere else so the material stays OS-consistent.
- **Beating heart (FR-3.1):** a heart `Shape` with the §7b gradient "glass" fill and a zone-colored glow. A `TimelineView(.animation)` reads `session.frame(now:)` and maps `contraction` to scale and brightness — the same `beatContraction` curve as the TUI (D-13), so beats land at identical times in both UIs. Honest idle (§7b): dimmed, the TUI's fixed ~48 bpm cadence while scanning/reconnecting; never a fake live beat.
- **BPM number (FR-3.2):** one hero number per screen (§7b); renders `displayedBPM` (the D-03 tween) in a large rounded font with monospaced digits, the unit as a small caption, zone-colored.
- **Zone palette (FR-2A.3):** `ZonePalette` in `NabzApp` — dynamic colors (`NSColor(name:dynamicProvider:)`, D-12) seeded from the §7b truecolor values: dark variant = canonical hex, light variant darkened for contrast; below-zones uses the secondary label color (FR-4.4, D-07). The heart gradient resolves per appearance the same way. Contrast target: ≥ 3:1 for the number and legend against the card surface in **both** appearances, checked with a contrast tool and recorded in the PR.
- **Sparkline (FR-3.3):** Swift Charts over `frame.window` (60 s, D-03), per-sample zone color, no axis chrome. `Canvas` only if per-sample coloring can't be expressed in Charts.
- **Zone legend (FR-3.4):** five Z1–Z5 segments with BPM ranges computed from HRmax + thresholds (the mockup's tooltip, made permanent), active zone highlighted **and named in text**; friendly labels as subtitles at most (D-07).
- **Status pill (FR-3.5):** sensor name · state, colored dot, contact indicator, elapsed time, active HRmax (D-02).
- **State visuals (FR-3.6):** the app column of the §7b table, driven by core `DisplayState`:

| State | App treatment |
|---|---|
| scanning | dim gray heart, idle cadence, "Scanning for sensors…" |
| connecting | dim heart, sensor name in the pill |
| live | zone-colored heart + number, full card |
| no contact | hollow heart, Z3 warning in the pill |
| reconnecting | dimmed, last BPM grayed, elapsed retained |
| alert (failed / unauthorized / bluetoothOff) | Z5 accent, one-line fix, "Open Bluetooth Settings" button to the Privacy › Bluetooth pane (R-1) |

- **Accessibility (§7b):** zone always named in text; `accessibilityLabel` on the hero ("72 beats per minute, zone 2"); Reduce Motion → the pulse becomes a subtle opacity change with no scale.
- **Appearance (FR-2A.2):** follows the system live — no relaunch, no in-app override.
- **CPU (NFR-3):** the pulse driver stops when the window is hidden or minimized.
- Latency instrumentation from SPEC-08 retained (NFR-1).

## Non-goals
Sidebar, Settings, device picking, packaging (SPEC-10). Phase-3 floating panel / menu bar. HRV. Changing any beat timing — that is core-owned (D-13).

## Acceptance criteria
- In `--simulate`, the heart visibly beats in time with the simulated RR-intervals; cutting RR from the simulator switches to BPM cadence without a visual break.
- BPM glides (never snaps); the sparkline scrolls; zone transitions recolor heart, number, and legend together; below-zone renders neutral, never Z1 (FR-4.4).
- All six visual states reachable by scripting the simulated source, each distinct, with the alert states carrying their actionable copy.
- Both appearances meet the contrast target, and toggling System Settings appearance mid-run updates every color live.
- Reduce Motion respected; a 45-minute simulated session stays steady with idle-to-light CPU (NFR-2, NFR-3); sample→render latency < 1 s (NFR-1).

## Test plan
Unit: zone→color mapping including `nil`, with both appearance variants resolving to different values; legend BPM ranges from HRmax/thresholds; state → copy table; Reduce-Motion branch. Manual: extended `--simulate` viewing in dark and light, appearance toggle mid-run, Reduce Motion on/off, window hide/minimize CPU check in Activity Monitor. The bar is qualitative as in SPEC-05 — tuning time is part of the spec.

## Dependencies
SPEC-08 (app shell, session model, core `HeartAnimation`).

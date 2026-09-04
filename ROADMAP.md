# Nabz — Roadmap

Execution plan for the phases and specs defined in [Nabz-PRD.md](./Nabz-PRD.md). One spec per session; each spec lists its own acceptance criteria and test plan under [specs/](./specs/).

## Phases

| Phase | Deliverable | Exit criteria |
|---|---|---|
| **1 — Terminal** | `nabz` TUI: live beat-synced heart, BPM, zones, sparkline | Phase-1 exit checklist, PRD §11 |
| **2 — SwiftUI app** | Windowed macOS app (Liquid Glass, dark/light) on `NabzCore` unchanged | Phase-2 exit checklist (below) |
| **3 — Desktop presence** | `MenuBarExtra` + floating `NSPanel` readout | Phase-3 spec set |
| **4 — Insights (stretch)** | HRV metrics, session recording/export | Not committed; PRD §13 |

## Phase 1 — spec execution order (simulation-first)

Spec numbers are stable identifiers; this is the **build order**. UI comes up on the simulated source first, so the hero feature (the beating heart) is visible and tunable long before hardware integration.

| Order | Spec | Depends on | Demoable outcome |
|---|---|---|---|
| 1 | [SPEC-01 — Core scaffolding & data model](./specs/SPEC-01-core-scaffolding.md) | — | `swift test` green; simulated stream prints samples |
| 2 | [SPEC-02 — HR Measurement parser](./specs/SPEC-02-hr-parser.md) | 01 | fully tested `0x2A37` parser |
| 3 | [SPEC-04 — TUI renderer skeleton](./specs/SPEC-04-tui-skeleton.md) | 01 | full-screen TUI showing live simulated BPM + states |
| 4 | [SPEC-05 — Beating-heart animation](./specs/SPEC-05-heart-animation.md) | 04 | **the hero**: beat-synced heart, zones, sparkline — on simulated data |
| 5 | [SPEC-03 — BLE source](./specs/SPEC-03-ble-source.md) | 01, 02 | same UI on a real Polar H10 |
| 6 | [SPEC-06 — CLI & config](./specs/SPEC-06-cli-config.md) | 03, 05 | full CLI surface, persisted preferences |
| 7 | [SPEC-07 — Packaging](./specs/SPEC-07-packaging.md) | 06 | installable `.app`-bundled CLI, permission walkthrough |

Rationale: the PRD's guiding rule is "Phase 1 ships one thing exceptionally well" (§1.1). This order front-loads that one thing and pushes the only hardware-dependent spec (03) to the point where everything around it already works.

## Phase 2 — spec execution order (simulation-first)

Same rule as Phase 1: the app comes up on the simulated source first, the hero is tuned strap-free, and hardware only matters for the closing spec's acceptance run. Decisions D-12…D-16 (PRD §14) were recorded when this set was written.

| Order | Spec | Depends on | Demoable outcome |
|---|---|---|---|
| 1 | [SPEC-08 — App scaffolding & view model](./specs/SPEC-08-app-scaffolding.md) | 07 | `swift run nabz-app --simulate` opens a window tracking simulated BPM + state; CI on Xcode 26 |
| 2 | [SPEC-09 — Glass dashboard: the hero heart card](./specs/SPEC-09-glass-dashboard.md) | 08 | **the hero, in glass**: beat-synced gradient heart, zones, sparkline, dark + light — on simulated data |
| 3 | [SPEC-10 — Sidebar, Settings, devices & packaging](./specs/SPEC-10-app-settings-packaging.md) | 09 | installable `Nabz.app` on a real Polar H10, preferences shared with the CLI |

Rationale: SPEC-08 opens with the one core change the app needs (promoting the shared beat-timing logic, D-13) so the boundary is fixed before any view exists; SPEC-09 is the only spec whose bar is qualitative, so it gets a whole session; SPEC-10 bundles everything that touches hardware, the filesystem, or the installer.

**Phase-2 exit checklist**

- [ ] 45-minute zone-2 session on real hardware in the app, once in dark and once in light appearance; readout correct and legible throughout.
- [ ] Mid-session disconnect auto-recovers in the app (FR-1.6); switching devices from Settings releases the old central (R-6, D-16).
- [ ] `--simulate` parity: the app and `nabz --simulate` beat on the same schedule (D-13) and show the same six states.
- [ ] Fresh-TCC grant is attributed to **Nabz** for both the app and the symlinked CLI (D-15).
- [ ] CI green on Xcode 26: build, unit tests, TUI smoke run, app smoke run (NFR-6).

## After Phase 2

The Phase-3 spec set is written when Phase 3 starts, consuming `NabzCore` verbatim (PRD §4). If a UI spec forces a core change, the abstraction is leaking — stop and fix the boundary first.

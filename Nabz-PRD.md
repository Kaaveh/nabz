# Nabz — Product Requirements Document

**Status:** Draft v1.2
**Owner:** Kaaveh
**Last updated:** 2026-07-23
**Platform:** macOS (Apple Silicon)

> **Brand note:** *Nabz* (نبض) means "pulse" — the product's one job in a word. The prior working name (*iBeat*) is dropped because the mark was already taken; all package, target, and CLI identifiers are renamed accordingly (see §5, §6).

---

## 1. Summary

Nabz is a native macOS application that connects to a Bluetooth Low Energy (BLE) heart-rate monitor — primary target **Polar H10** — and displays the wearer's real-time heartbeat. The first release is a polished terminal (TUI) experience: an animated heart that beats in sync with the actual pulse, a large live BPM readout, a rolling trend sparkline, and heart-rate-zone coloring, styled with the clean, colorful aesthetic of a modern agent CLI.

**The heartbeat is the product.** Everything in Phase 1 — the animation, the BPM readout, the zones, the sparkline — serves one job: showing the live pulse beautifully and accurately. Heart-rate variability (HRV) and other analytics are explicitly *not* the point of the first release; they are a nice-to-have that later phases unlock on top of the same data stream (see §1.1 and §12).

The product is intentionally phased. A single, UI-agnostic **core** (BLE + domain logic) is built once and reused across every phase; only the presentation layer changes.

- **Phase 1 — Terminal (TUI):** animated, colored terminal readout of the live heartbeat. *This document's primary focus.*
- **Phase 2 — SwiftUI app:** a windowed macOS app on the same core.
- **Phase 3 — Desktop presence:** menu-bar item and optional always-on-top floating readout.
- **Phase 4 (stretch) — Insights:** HRV metrics and session recording.

### 1.1 Feature priority (what matters, and when)

| Priority | Feature | Phase | Notes |
|---|---|---|---|
| **P0 — core** | Live heartbeat: beat-synced animation + live BPM | 1 | The hero. Must feel instant and accurate. |
| **P0 — core** | Reliable BLE connection to Polar H10 / standard HR sensors | 1 | Enables everything else. |
| **P1** | HR zones, trend sparkline, connection/status states | 1 | Directly supports the heartbeat readout. |
| **P1** | Simulation mode (strap-free dev/demo) | 1 | Lets the hero feature be built and tuned without hardware. |
| **P2 — nice-to-have** | HRV metrics (RMSSD, resting HRV trends) | 4 | A *vehicle for later phases*, not a Phase-1 goal. The RR-interval data needed for it already flows in Phase 1, so no rework is required to add it later. |
| **P2 — nice-to-have** | Session recording & export | 4 | Builds on the same stream. |

The guiding rule: if a proposed Phase-1 change trades heartbeat fidelity for HRV or analytics groundwork, defer it. Phase 1 ships one thing exceptionally well.

---

## 2. Goals & Non-Goals

### Goals
- Connect reliably to a Polar H10 (and any standard BLE HR sensor) over BLE on macOS.
- Show the real-time heartbeat — beat-synced animation and live BPM — with sub-second perceived latency.
- Render a smooth, beat-synced heart animation in the terminal, with zone-based coloring.
- Ship a reusable core so Phases 2 and 3 add UI without rewriting device logic.
- Support a strap-free development/demo mode (simulated heart-rate source).

### Non-Goals (for now)
- **HRV metrics and analytics in Phase 1.** RR-interval data is captured so HRV *can* be added later, but computing or displaying it is out of scope until Phase 4.
- Cross-platform support (Windows/Linux/iOS). macOS only in Phase 1.
- Cloud sync, accounts, or a backend service.
- Long-term data storage or analytics (recording is a Phase-4 stretch).
- Raw ECG / accelerometer streaming via Polar's proprietary PMD service (stretch only).
- Support for chest straps that do **not** expose the standard Heart Rate Service.

---

## 3. Target User & Context

A single primary user (the developer/owner) on an Apple Silicon Mac running a recent macOS, wearing a Polar H10 chest strap. The user is a senior engineer comfortable in the terminal and interested in training (zone-2 focus) and, longer term, heart-rate variability. The experience should feel fast, precise, and visually satisfying rather than utilitarian.

---

## 4. Product Phases / Roadmap

| Phase | Deliverable | Presentation | Core reuse |
|-------|-------------|--------------|------------|
| 1 | Terminal heartbeat readout | Hand-rolled ANSI TUI | `NabzCore` (new) |
| 2 | Windowed app | SwiftUI + Observation, Liquid Glass, dark/light (macOS 26+) | `NabzCore` (verbatim) |
| 3 | Desktop presence | `MenuBarExtra` + floating window | `NabzCore` (verbatim) |
| 4 (stretch) | Insights | HRV metrics, session recording/export | `NabzCore` (extended) |

The phase boundary is deliberately drawn at the **presentation layer**. If a proposed change forces edits to `NabzCore` to satisfy a UI, treat that as a signal that the abstraction is leaking and reconsider.

---

## 5. Tech Stack (Finalized)

### Language & tooling
- **Swift 6.x** — current stable toolchain, strict concurrency enabled. The exact Swift/Xcode versions are pinned in CI when SPEC-01 lands, not in this document, so the PRD doesn't rot.
- **Swift Package Manager** for build and dependency management.
- **swift-testing** for unit tests (with XCTest interop available if needed).

### `NabzCore` — shared, UI-agnostic
- **CoreBluetooth** (native) for BLE central role, scanning, connection lifecycle, and GATT.
- Domain layer exposing heart-rate data as an **`AsyncStream` / `AsyncSequence`**.
- **Concurrency model:** `NabzCore` compiles clean under Swift 6 strict concurrency. `BLEHeartRateSource` is an actor wrapping the CoreBluetooth delegate; UI-facing streams use `AsyncStream(bufferingPolicy: .bufferingNewest(1))` so consumers always render the latest sample and never build a backlog.
- A **`HeartRateSource` protocol** with two implementations:
  - `BLEHeartRateSource` (CoreBluetooth-backed).
  - `SimulatedHeartRateSource` (deterministic/randomized generator for dev & tests).

### Phase 1 presentation — terminal
- **Hand-rolled ANSI rendering**: 24-bit truecolor, cursor positioning, alternate screen buffer, raw mode. Chosen for precise control over beat-synced animation timing.
- **swift-argument-parser** for the CLI surface.
- *Alternative considered:* TUIkit / SwiftTUI (SwiftUI-like TUI frameworks). Viable and eases the Phase 2 transition, but young (v0.x) and less suited to frame-accurate custom animation. Kept as a fallback; the core stays separate regardless.

### Phase 2 presentation — SwiftUI
- **SwiftUI** views bound to `@Observable` (Observation framework) view models fed by the core's `AsyncStream`.
- **Liquid Glass design language** (macOS 26 Tahoe+). The app adopts Apple's Liquid Glass material for its surfaces — cards, toolbar/sidebar, and the floating readout — via SwiftUI's `.glassEffect()`, grouping related surfaces in a `GlassEffectContainer` and using `glassEffectID(_:in:)` for coherent morph transitions (e.g. the pulsing heart card). Lean on system components so the material, blur, and specular highlights come "for free" and stay consistent with the OS. See §7a.
- **Full dark- and light-mode support.** All views are appearance-adaptive: colors (including the HR-zone palette and the heart gradient) come from semantic/asset-catalog colors that resolve per appearance, and the UI respects the system setting live (no relaunch). Both modes are first-class, not one theme with an afterthought inversion.
- **Baseline:** Phase 2 targets **macOS 26 (Tahoe) or later**, since Liquid Glass APIs require it. (Phase 1's TUI has no such floor.)

### Phase 3 presentation — desktop
- **`MenuBarExtra`** for live BPM in the menu bar.
- Optional small always-on-top window via a borderless `NSPanel` (floating level). **Not** WidgetKit — see §10.

### Rationale (why Swift over Rust)
The BLE layer is the expensive, high-value component and the one piece reused across all three phases. In Swift it is CoreBluetooth, which carries over to SwiftUI and to the desktop app unchanged. A Rust implementation (`btleplug` + `ratatui`) would produce a nicer Phase-1 TUI with less effort, but would then require discarding the device layer at Phase 2 or bridging Rust→Swift via FFI. Rust's core strength (rich TUI widgets) is this project's smallest need — a single animated screen — while Swift's strength (one device core reused everywhere) is its largest.

---

## 6. Architecture

```
┌─────────────────────────────────────────────┐
│                NabzCore                      │
│  (Swift Package, UI-agnostic, all phases)    │
│                                              │
│  • HeartRateSource (protocol)                │
│     ├─ BLEHeartRateSource (CoreBluetooth)    │
│     └─ SimulatedHeartRateSource              │
│  • HeartRateMeasurementParser (pure)         │
│  • Domain models: HeartRateSample,           │
│    RRInterval, ConnectionState, HRZone       │
│  • AsyncStream<HeartRateSample> output       │
└───────────────┬──────────────┬───────────────┘
                │              │
      ┌─────────▼───┐   ┌──────▼────────┐   ┌──────────────┐
      │  NabzTUI    │   │  NabzApp      │   │  NabzMenu    │
      │ (Phase 1)   │   │ (Phase 2)     │   │  (Phase 3)   │
      │ ANSI render │   │ SwiftUI       │   │ MenuBarExtra │
      └─────────────┘   └───────────────┘   └──────────────┘
```

**Principles**
- `NabzCore` has **no UI dependencies** and no knowledge of how data is displayed.
- The parser (`HeartRateMeasurementParser`) is **pure** (bytes → `HeartRateSample`) and fully unit-tested.
- All device access flows through `HeartRateSource`, so any presentation can run against the simulated source.
- Connection state is modeled explicitly as a state machine (see §9) and streamed to the UI.
- RR-intervals are parsed and carried through the model from day one — not because Phase 1 analyzes them, but because they drive the beat-synced animation *and* leave HRV as a drop-in Phase-4 addition with zero core rework.

---

## 7. Functional Requirements — Phase 1 (Terminal)

### 7.1 Device discovery & connection
- **FR-1.1** Scan for peripherals advertising the Heart Rate Service (`0x180D`).
- **FR-1.2** `--list` prints discovered sensors (name, identifier, RSSI) and exits.
- **FR-1.3** Auto-connect to the first/preferred sensor, or a specific one via `--device <name|uuid>`.
- **FR-1.4** Remember the last-used sensor and prefer it on next launch (persisted in the config file, see D-08).
- **FR-1.5** Discover the HR Measurement characteristic (`0x2A37`) and subscribe to notifications.
- **FR-1.6** Auto-reconnect on disconnect with exponential backoff: 1 s doubling to a 30 s cap, ±20 % jitter, retrying indefinitely while the UI shows *reconnecting*.
- **FR-1.7** Clean teardown on `Ctrl-C` (SIGINT) and SIGTERM: unsubscribe, disconnect, restore terminal — through a single teardown path reachable from every exit. SIGWINCH triggers a redraw (FR-3.7).

### 7.2 Heart-rate parsing
- **FR-2.1** Parse `0x2A37` per spec (§Appendix A): handle UINT8/UINT16 BPM, sensor-contact status, and RR-intervals.
- **FR-2.2** Emit a `HeartRateSample` per notification with BPM, contact status, RR-interval(s), and timestamp.
- **FR-2.3** Tolerate malformed/short payloads without crashing (log and skip).

### 7.3 Terminal UI (the heartbeat readout)
- **FR-3.1 Beating heart (hero element):** an ASCII/braille heart that visibly contracts on each beat, timed to incoming **RR-intervals** for a realistic pulse; fall back to BPM-derived cadence when RR is absent.
- **FR-3.2 Live BPM:** large, legible number that updates smoothly (ease transitions rather than snapping).
- **FR-3.3 Trend sparkline:** a rolling sparkline of the last N seconds of BPM (block/braille glyphs).
- **FR-3.4 HR zones:** color the heart and BPM by zone (see §7.4); default zones from configurable HRmax.
- **FR-3.5 Status line:** connection state, sensor name, sensor-contact indicator, elapsed time.
- **FR-3.6 States:** distinct visuals for *scanning*, *connecting*, *connected/live*, *no contact*, *reconnecting*, *error*.
- **FR-3.7 Resilience:** redraw correctly on terminal resize; degrade gracefully if truecolor is unsupported (256-color fallback).

### 7.4 Heart-rate zones
- **FR-4.1** Configurable HRmax (explicit value preferred over an age formula).
- **FR-4.2** Five zones by %HRmax — Z1 50–60, Z2 60–70, Z3 70–80, Z4 80–90, Z5 90–100 — each with a distinct color. (Zone-2 emphasis for training use.)
- **FR-4.3** Thresholds overridable via config.
- **FR-4.4** BPM below 50 % HRmax is *below zones*: rendered with the neutral resting treatment (§7b), never colored as Z1.

### 7.5 Simulation mode
- **FR-5.1** `--simulate` runs the full UI against `SimulatedHeartRateSource` with no hardware.
- **FR-5.2** Simulated data produces plausible BPM drift and RR-intervals so the animation can be tuned strap-free.

### 7.6 CLI surface (indicative)
```
nabz                      # scan, connect to preferred sensor, run live UI
nabz --list               # list discoverable HR sensors and exit
nabz --device "Polar H10 12345678"
nabz --simulate           # run with a fake heart-rate source
nabz --max-hr 190         # set HRmax for zone calculation
nabz --no-color           # disable coloring
nabz --verbose            # mirror diagnostics to stderr (NFR-7)
```

---

## 7a. UI Requirements — Phase 2 (Desktop App, forward-looking)

Captured now so the core and view-model boundary account for them; detailed specs come with the Phase-2 spec set.

- **FR-2A.1 Liquid Glass surfaces:** primary surfaces (hero heart card, sidebar/toolbar, floating readout) use Liquid Glass via `.glassEffect()`, grouped in a `GlassEffectContainer`; prefer standard SwiftUI controls so the material stays OS-consistent.
- **FR-2A.2 Appearance adaptivity:** full dark- and light-mode support; all colors resolve from semantic/asset-catalog colors and update live with the system appearance setting.
- **FR-2A.3 Zone & heart color fidelity:** the five HR-zone colors and the heart gradient remain legible and on-brand in **both** appearances (validate contrast in each mode, not just one).
- **FR-2A.4 Motion continuity:** the beat-synced pulse (Phase-1 hero, FR-3.1) carries into the app as an animated Liquid Glass element, using `glassEffectID(_:in:)` for smooth state transitions.
- **FR-2A.5 Graceful degradation:** if run on a pre-macOS-26 system (below the Liquid Glass floor), the app either refuses to launch with a clear message or falls back to a plain material — decided in the Phase-2 spec, not left implicit.

---

## 7b. Design Language & UI Guidelines (canonical, all phases)

The images under `mockup/` are directional prototypes. **Where a mockup disagrees with this section, this section wins.**

### Brand & hero
- One motif: the **pulse**. The heart silhouette is shared across every phase — dot-matrix/braille heart in the TUI (the brand mark), gradient "glass" heart in the Phase-2 app, minimal heart glyph in the menu bar (`♥ 72`).
- One hero BPM number per screen. The terminal mockup's redundant `BPM: 72` header row is dropped; the big number is the readout.

### Zone palette (canonical values)

| Zone | Hue | Truecolor | 256-color | Phase-2 |
|---|---|---|---|---|
| Below zones | neutral gray | `#9CA3AF` | 248 | semantic secondary label color |
| Z1 | blue | `#3B82F6` | 33 | asset-catalog color, dark/light variants |
| Z2 | green | `#22C55E` | 41 | 〃 |
| Z3 | yellow | `#EAB308` | 178 | 〃 |
| Z4 | orange | `#F97316` | 208 | 〃 |
| Z5 | red | `#EF4444` | 203 | 〃 |

Phase 2 resolves these through semantic/asset-catalog colors with per-appearance variants, contrast-validated in both modes (FR-2A.3). The TUI uses the truecolor values with the listed 256-color fallbacks (FR-3.7).

### Layout & typography (TUI)
- Heart left, big BPM right (as mocked); block-glyph digits ~5–7 rows tall for the BPM.
- Full-width sparkline beneath, zone-colored per sample; status line at the bottom; zone legend under the status line with the active zone highlighted.
- Minimum terminal 80×24. Degradation order when smaller: drop zone legend → drop sparkline → heart + BPM only. Never clip glyphs mid-character.
- The TUI runs full-screen in the alternate buffer — no shell prompt is visible (the prompt in the terminal mockup is an artifact).

### Motion
- **Beat:** fast systole (~120 ms contraction) then an eased diastole release that lasts until the next scheduled beat; beats are scheduled from RR-intervals with BPM-derived fallback (FR-3.1).
- **BPM number:** ~300 ms ease-out tween per D-03; the number never snaps.
- **Stale data never fakes life:** while scanning/reconnecting the heart idles at a slow fixed cadence, dimmed — an honest "not your pulse" state.

### State visuals (FR-3.6)
| State | Treatment |
|---|---|
| scanning | dim gray heart, "Scanning for sensors…" |
| connecting | dim heart, sensor name in status |
| live | zone-colored heart + BPM, full UI |
| no contact | hollow/dimmed heart, warning in Z3 yellow |
| reconnecting | dimmed, last BPM grayed, elapsed time retained |
| error / unauthorized / bluetoothOff | Z5 red accent + one-line actionable fix (e.g. the TCC grant path, R-1) |

### Accessibility
- Never color-only signaling: the active zone is always named in text (status line + legend).
- `--no-color` is fully functional — zones shown textually, heart in default foreground.
- Zone colors stay legible on both dark and light terminal schemes; Phase 2 validates contrast in both appearances.

### Mockup errata (recorded so specs don't inherit them)
- Desktop sidebar's *History* and *Trends* are Phase-4 aspirational; the Phase-2 app ships Dashboard + Settings.
- Zone labels "Resting / Warm Up / Fat Burn / Cardio / Peak" superseded by D-07.
- "72 BPM · Zone 2" is inconsistent (below zones at any plausible HRmax; FR-4.4).
- The "widget" image depicts the floating `NSPanel` readout — Phase 3 is `MenuBarExtra` + `NSPanel`, not WidgetKit (R-5).

---

## 8. Non-Functional Requirements

- **NFR-1 Latency:** perceived BPM update latency < ~1 s (bounded by the sensor's notification cadence).
- **NFR-2 Animation smoothness:** render loop targets a steady frame cadence (e.g. 30–60 fps) without visible tearing or flicker; use the alternate screen buffer and diff-based redraws where practical.
- **NFR-3 CPU:** idle-to-light CPU footprint; the render loop must not busy-spin.
- **NFR-4 Reliability:** survive transient disconnects via auto-reconnect; never leave the terminal in a broken state on exit or crash.
- **NFR-5 Permissions:** handle the `CBManager` `.unauthorized` / `.poweredOff` states with a clear, actionable message (see §10).
- **NFR-6 Testability:** parser and zone logic covered by unit tests; UI runnable against the simulated source in CI. CI = GitHub Actions on a macOS runner: `swift build` + `swift test` + a scripted `--simulate` smoke run. BLE hardware paths are excluded from CI by design.
- **NFR-7 Logging:** the TUI owns stdout and the screen — nothing else writes to it. Diagnostics go through `os.Logger` in `NabzCore`; `--verbose` mirrors them to stderr (redirect to a file while the TUI is active).

---

## 9. Data Model

```swift
struct HeartRateSample {
    let bpm: Int
    let contact: SensorContact          // .unsupported, .noContact, .contact
    let rrIntervals: [Double]           // seconds (converted from 1/1024s units)
    let timestamp: Date
}

enum SensorContact { case unsupported, noContact, contact }

enum ConnectionState {
    case idle
    case scanning
    case connecting(peripheral: String)
    case connected(peripheral: String)
    case reconnecting
    case failed(reason: String)
    case unauthorized
    case bluetoothOff
}

enum HRZone: Int { case z1 = 1, z2, z3, z4, z5 }   // derived from bpm + HRmax
```

**`ConnectionState` transitions**

| From | To | Trigger |
|---|---|---|
| `idle` | `scanning` | launch / manual rescan |
| `scanning` | `connecting` | target peripheral discovered |
| `connecting` | `connected` | HR characteristic subscribed |
| `connecting` | `failed` | timeout or GATT error |
| `connected` | `reconnecting` | link dropped |
| `reconnecting` | `connected` | backoff attempt succeeds (retries are infinite, FR-1.6) |
| any | `unauthorized` / `bluetoothOff` | `CBManager` state change; both are exits from the normal flow with actionable messaging (NFR-5) |

> `rrIntervals` is captured on every sample even though Phase 1 only uses it for beat-sync timing. This is the single design choice that makes HRV a later add-on rather than a rewrite.

---

## 10. Technical Considerations & Risks

- **R-1 Bluetooth permission (macOS TCC).** A bare SwiftPM executable has no `Info.plist`, so macOS attributes the Bluetooth request to the launching terminal app. Mitigation: instruct the user to grant Terminal/iTerm Bluetooth access under **System Settings → Privacy & Security → Bluetooth**, or bundle the CLI as a minimal `.app` with `NSBluetoothAlwaysUsageDescription`. Detect and message the `.unauthorized` state explicitly.
- **R-2 Run loop lifetime.** CoreBluetooth delegate callbacks require an active run loop. Structure the executable around an async entry point that stays alive on the sample stream, with SIGINT handling for clean teardown (Swift 6.4's `async defer` simplifies cleanup).
- **R-3 RR-interval availability.** RR-intervals are present only when the sensor sets the RR flag. The H10 provides them; still, fall back to BPM-derived beat cadence (FR-3.1) so the animation works with any HR sensor.
- **R-4 Terminal color support.** Truecolor is not universal. Provide a 256-color fallback and a `--no-color` mode; detect via `$COLORTERM` where possible.
- **R-5 Phase 3 widget limitation.** macOS widgets are snapshot-based and cannot maintain a live BLE connection. "Live on desktop" is delivered via `MenuBarExtra` and an optional floating `NSPanel`, not WidgetKit. Bake this into Phase 3 scope from the start.
- **R-6 Multiple concurrent centrals.** Only one process should hold the sensor connection at a time; document that the SwiftUI app and the CLI shouldn't both connect simultaneously.
- **R-7 Brand/name collision.** The prior name was already taken. "Nabz" is the committed brand; verify availability of the CLI binary name, any future App Store name, and the domain before external release.

---

## 11. Success Criteria (Phase 1)

Phase 1 is done when, on the owner's Mac with a Polar H10:

- Launching `nabz` finds and connects to the strap within a few seconds, unattended.
- The on-screen heart visibly beats in time with the real pulse (RR-synced), and the BPM number tracks the sensor with sub-second perceived lag.
- The readout stays correct and legible across a full ~45-minute zone-2 session, including a mid-session disconnect that auto-recovers without breaking the terminal.
- `nabz --simulate` reproduces the full experience with no hardware, so the animation can be developed and tuned strap-free.
- Parser and zone logic pass their unit tests in CI.

**Phase-1 exit checklist**

- [ ] 45-minute zone-2 session on real hardware; readout correct and legible throughout.
- [ ] Mid-session disconnect auto-recovers (FR-1.6); terminal never left broken (FR-1.7).
- [ ] Latency measured, not felt: in `--simulate`, sample-timestamp → render-timestamp delta < 1 s (NFR-1), instrumented by the simulated source.
- [ ] `--simulate` reproduces the full experience with visual parity to the live path.
- [ ] CI green: build, unit tests, simulate smoke run (NFR-6).

The bar is otherwise qualitative on purpose: the single question is *"does watching your own heartbeat in the terminal feel instant, accurate, and satisfying?"*

---

## 12. Milestones (Spec-Driven Breakdown)

One-spec-per-session decomposition, matching the `SPEC-NN-name.md` + decision-log workflow. Spec numbering is stable; **execution order is simulation-first** and defined in [ROADMAP.md](./ROADMAP.md) — the TUI specs (04, 05) run against `SimulatedHeartRateSource` before the BLE source (03) lands, so the hero feature is demoable earliest.

- **[SPEC-01 — Core scaffolding & data model](./specs/SPEC-01-core-scaffolding.md).** SPM package, `HeartRateSource` protocol, domain models, `SimulatedHeartRateSource`.
- **[SPEC-02 — HR Measurement parser](./specs/SPEC-02-hr-parser.md).** Pure `0x2A37` parser + full unit-test suite (edge cases: UINT16 BPM, no-contact, multiple RR-intervals, short payloads).
- **[SPEC-03 — BLE source](./specs/SPEC-03-ble-source.md).** CoreBluetooth central: scan → connect → subscribe → stream; reconnection & state machine; permission-state handling.
- **[SPEC-04 — TUI renderer skeleton](./specs/SPEC-04-tui-skeleton.md).** Raw mode, alternate buffer, render loop, resize handling, state-driven layout (scanning/connecting/live/error).
- **[SPEC-05 — Beating-heart animation](./specs/SPEC-05-heart-animation.md).** RR-synced pulse, eased BPM transitions, zone coloring, sparkline, truecolor/256-color fallback.
- **[SPEC-06 — CLI & config](./specs/SPEC-06-cli-config.md).** swift-argument-parser surface, preferred-device persistence, HRmax/zone config, `--simulate`/`--list`/`--no-color`.
- **[SPEC-07 — Packaging](./specs/SPEC-07-packaging.md).** `.app` bundle with `NSBluetoothAlwaysUsageDescription`, install script, README with the permission walkthrough.

Phases 2–3 get their own spec sets later, each consuming `NabzCore` unchanged.

---

## 13. Future / Stretch

*All items below are nice-to-haves layered on the Phase-1 heartbeat core — not commitments.*

- **HRV metrics** from RR-intervals (RMSSD, resting HRV trends) — the flagship stretch. The RR data already flows in Phase 1, so this is additive. Given the zone-2/longevity interest, it's the most likely feature to graduate from "nice-to-have" to a real Phase-4 deliverable.
- **Session recording & export** (CSV/FIT) for post-workout review.
- **Raw ECG / accelerometer** via Polar's proprietary PMD service.
- **Multi-sensor** support and sensor comparison.
- **iOS companion** on the same core (CoreBluetooth is shared between macOS and iOS).

---

## 14. Resolved Decisions

These were open at draft; here is where they land. IDs follow the decision-log convention so spec sessions can reference them.

- **D-00 — Brand: "Nabz".** The working name *iBeat* was already taken, so the product is renamed **Nabz** (نبض, "pulse"). All identifiers follow: package `NabzCore`, targets `NabzTUI` / `NabzApp` / `NabzMenu`, CLI binary `nabz`. Confirm binary-name, store-name, and domain availability before any external release (see R-7).
- **D-01 — Packaging: raw CLI binary for Phase 1 development; `.app` bundle deferred to SPEC-07.** Build and iterate as a plain SPM executable — the fastest path on CLT + Cursor with no bundling step. The `.app` bundle (carrying `NSBluetoothAlwaysUsageDescription`) is added in the packaging spec, when a clean distributable artifact actually matters. Practical note: the Bluetooth permission attributes to whichever process launches the binary, so you grant it once to Terminal (for `swift run`) and once to Cursor (for in-editor LLDB debugging) — both one-time. See R-1.
- **D-02 — HRmax: never gate the first run.** Ship a configurable placeholder default (190 bpm — documented as a placeholder, not a physiological claim), compute zones from whatever HRmax is active, and treat `--max-hr` / config as the real path. The active HRmax is shown in the status line so the value in play is never ambiguous. Optional age-based auto-fill uses the Tanaka formula (208 − 0.7·age), which is better supported than 220 − age; an explicit value always wins. This avoids false precision and fits real training use. See FR-4.1, §7.4.
- **D-03 — Sparkline & smoothing: concrete starting values, tuned in `--simulate`.** Sparkline = a 60 s rolling window (configurable), plotting raw samples so the trend stays honest. Displayed BPM = eased interpolation (ease-out, ~300 ms) toward each new sample — a tween on the number itself, not a moving average, so it animates smoothly without lagging the true reading. The heart's pulse stays RR-driven and independent of this (FR-3.1). See FR-3.2, FR-3.3.
- **D-04 — Renderer: hand-rolled ANSI, committed.** A single animated screen needs frame-accurate, beat-synced timing, and the real reuse boundary is `NabzCore`, not the view code — so a SwiftUI-shaped TUI would not meaningfully reduce Phase 2 work. TUIkit/SwiftTUI remains a fallback only if the render loop becomes a maintenance burden. See §5.
- **D-06 — Phase 2 app: Liquid Glass + full dark/light mode, committed.** The SwiftUI desktop app adopts Apple's **Liquid Glass** design language (macOS 26 Tahoe+) via `.glassEffect()` / `GlassEffectContainer` / `glassEffectID(_:in:)`, and supports **both dark and light appearance** as first-class, with all zone/heart colors resolving from semantic/asset-catalog colors. This sets a **macOS 26+ floor for Phase 2 only** — Phase 1's TUI keeps no such requirement. Pre-26 fallback behavior is decided in the Phase-2 spec (see FR-2A.5). See §5, §7a.
- **D-07 — Zone naming: Z1–Z5 by %HRmax is canonical.** The friendly labels in the desktop mockup ("Resting / Warm Up / Fat Burn / Cardio / Peak") are not canonical — permitted as subtitles at most. BPM below 50 % HRmax is *below zones* with a neutral treatment (FR-4.4), never Z1. Where mockups disagree (e.g. 72 bpm labeled "Zone 2"), §7b supersedes them.
- **D-08 — Config & persistence: one `Codable` JSON file at `~/.config/nabz/config.json`.** Holds preferred device, HRmax, and zone overrides. No UserDefaults — an explicit file suits a bundle-less CLI, is trivially inspectable, and adds zero dependencies.
- **D-05 — HRV is a next-phase nice-to-have, not a Phase-1 feature.** Phase 1 optimizes for one thing: a beautiful, accurate live heartbeat. RR-intervals are captured and modeled from the start (§9) purely so HRV drops in at Phase 4 without touching the core — but no HRV computation or display ships before then. See §1.1, §13.
- **D-09 — TUI lives in its own `NabzTUI` target, not `NabzCore`.** The hand-rolled renderer (D-04) is Phase-1 presentation, so it sits in a `NabzTUI` library depending on `NabzCore` (never the reverse); the `nabz` executable is a thin `@main` over it. This keeps the reuse boundary honest (Phases 2–3 add their own presentation on the same core, PRD §4/§6) and makes the pure layout/diff logic unit-testable without dragging terminal I/O into the core. See §5, §6.
- **D-10 — Raw mode keeps `ISIG`; teardown is a signal-safe global restore.** The TUI disables `ICANON`/`ECHO` but leaves `ISIG` on, so Ctrl-C/Ctrl-\ still raise signals whose handler restores the terminal (`tcsetattr` + ANSI `write`, both async-signal-safe) and re-raises — one restore path reachable from SIGINT/SIGTERM/crash and `atexit` (FR-1.7, NFR-4). `q` quits gracefully via a flag; `NABZ_SMOKE_FRAMES=N` renders N frames then exits, giving the NFR-6 CI smoke run a no-pty hook. See §7.3, §8.
- **D-11 — Name-collision check cleared for the CLI; App-Store name and domain deferred (R-7).** As of 2026-07-24 the `nabz` binary name is free on Homebrew (formula and cask), npm, PyPI, and crates.io, with no PATH collision; GitHub has only a handful of unrelated near-zero-star repos. `nabz.app`/`.dev`/`.io` all resolve DNS (taken) and the App Store name is not programmatically checkable — both are Phase-2+ concerns and revisited before any external release. Packaging ships the CLI name as-is. See R-7, SPEC-07.

---

## Appendix A — BLE Reference

**Heart Rate Service** — UUID `0x180D`

| Characteristic | UUID | Properties | Use |
|---|---|---|---|
| Heart Rate Measurement | `0x2A37` | Notify | Live BPM + optional RR-intervals |
| Body Sensor Location | `0x2A38` | Read (optional) | Sensor placement |
| Heart Rate Control Point | `0x2A39` | Write (optional) | Reset energy expended |

**Heart Rate Measurement (`0x2A37`) payload**

- **Octet 0 — Flags:**
  - bit 0: HR value format (0 = UINT8, 1 = UINT16)
  - bits 1–2: Sensor contact status (0/1 = unsupported, 2 = supported/no contact, 3 = supported/contact)
  - bit 3: Energy Expended present
  - bit 4: RR-Interval present
  - bits 5–7: reserved
- **HR value:** UINT8 (1 octet) or UINT16 (2 octets, little-endian) per bit 0.
- **Energy Expended:** UINT16 (kJ), present if bit 3.
- **RR-Interval(s):** one or more UINT16, resolution **1/1024 s**, present if bit 4. Convert to seconds by dividing by 1024.

**Notes**
- Polar H10 also exposes a proprietary **PMD service** for raw ECG/accelerometer; not required for BPM + RR (stretch only).
- Notification cadence is typically ~1 Hz; RR-intervals give exact inter-beat timing for animation sync.

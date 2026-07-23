# SPEC-01 — Core scaffolding & data model

## Goal
Stand up the SPM workspace and the UI-agnostic heart of the product: domain models, the `HeartRateSource` protocol, and a working `SimulatedHeartRateSource`, so every later spec builds on a testable, hardware-free core.

## References
PRD §5 (tech stack), §6 (architecture), §9 (data model), §7.5 (simulation), D-05, D-08. NFR-6 (CI), NFR-7 (logging).

## Scope
- SPM package with targets `NabzCore` (library) and `nabz` (executable stub that prints streamed samples), plus a `NabzCoreTests` target using swift-testing.
- Swift 6 strict concurrency enabled package-wide.
- Domain models exactly as PRD §9: `HeartRateSample`, `SensorContact`, `ConnectionState`, `HRZone`.
- `HeartRateSource` protocol exposing `AsyncStream<HeartRateSample>` (buffering `.bufferingNewest(1)`) and a `ConnectionState` stream.
- `SimulatedHeartRateSource`: plausible BPM drift and RR-intervals (FR-5.2); deterministic when seeded (for tests), randomized by default. Emits sample timestamps so latency can be instrumented later (§11 checklist).
- Zone derivation logic: `HRZone` from BPM + HRmax per §7.4, including *below zones* (FR-4.4).
- `os.Logger` wiring in core (NFR-7).
- GitHub Actions workflow: `swift build` + `swift test` on a macOS runner; pin the Swift/Xcode version here (§5).

## Non-goals
CoreBluetooth (SPEC-03), any TUI rendering (SPEC-04/05), argument parsing and config file (SPEC-06 — the executable stub takes no flags yet).

## Acceptance criteria
- `swift run nabz` streams simulated samples as plain text lines and exits cleanly on Ctrl-C.
- A seeded simulator run is reproducible.
- Zone derivation matches §7.4 boundaries exactly, including below-zone and Z5 upper edge.
- `NabzCore` has no UI or terminal dependencies (§6 principles).
- CI is green.

## Test plan
swift-testing unit tests: zone boundaries (49 %/50 %/60 %/…/100 %/above), seeded-simulator determinism, stream delivers latest-value semantics. CI runs them.

## Dependencies
None — first spec.

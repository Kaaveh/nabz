# SPEC-02 — HR Measurement parser

## Goal
A pure, fully unit-tested parser for the BLE Heart Rate Measurement characteristic (`0x2A37`): bytes in, `HeartRateSample` out. This is the correctness core of the whole product.

## References
PRD §7.2 (FR-2.1…2.3), §9, Appendix A.

## Scope
- `HeartRateMeasurementParser`: pure function/struct in `NabzCore`, no I/O, no CoreBluetooth types (takes `Data`, returns `HeartRateSample?` or a typed parse error).
- Full flag handling per Appendix A: UINT8/UINT16 BPM, sensor-contact bits, Energy Expended present (skipped over, not surfaced), RR-interval list with 1/1024 s → seconds conversion.
- Malformed/short payloads: never crash; return an error the caller logs and skips (FR-2.3).

## Non-goals
Subscribing to the characteristic (SPEC-03). Interpreting RR-intervals (animation: SPEC-05; HRV: Phase 4).

## Acceptance criteria
- Parses every valid flag combination correctly, including multiple RR-intervals in one notification.
- UINT16 BPM values > 255 round-trip correctly (little-endian).
- Zero-length, 1-byte, and truncated-RR payloads return errors, never trap.
- Parser remains pure: no logging, no side effects inside parsing.

## Test plan
Exhaustive swift-testing suite with hand-built byte fixtures: UINT8 + contact variants, UINT16 BPM, energy-expended present, 1/2/3 RR-intervals, RR conversion precision (e.g. `1024 → 1.0 s`, `512 → 0.5 s`), each malformed case. This suite is the spec's main deliverable alongside the parser itself.

## Dependencies
SPEC-01 (models, package).

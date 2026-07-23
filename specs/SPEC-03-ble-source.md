# SPEC-03 — BLE source

## Goal
The real device path: a CoreBluetooth-backed `HeartRateSource` that scans, connects to a Polar H10 (or any standard HR sensor), subscribes to `0x2A37`, and streams parsed samples — with explicit connection-state modeling and auto-reconnect.

## References
PRD §7.1 (FR-1.1…1.7), §9 (state machine + transition table), §10 (R-1, R-2, R-3, R-6), NFR-4, NFR-5, Appendix A.

## Scope
- `BLEHeartRateSource` as an actor wrapping `CBCentralManager` (§5 concurrency model).
- Scan for Heart Rate Service `0x180D`; connect to first/named/preferred peripheral (FR-1.3; preference *persistence* arrives in SPEC-06 — this spec accepts an optional target identifier).
- Discover `0x2A37`, subscribe, feed notifications through the SPEC-02 parser into the sample stream (FR-1.5, FR-2.2).
- `ConnectionState` machine exactly per the §9 transition table, streamed to consumers.
- Auto-reconnect: exponential backoff 1 s → 30 s cap, ±20 % jitter, infinite retries (FR-1.6).
- `.unauthorized` / `.poweredOff` surfaced as their dedicated states with actionable messaging hooks (NFR-5, R-1).
- Run-loop/lifetime handling so delegate callbacks fire in a CLI process (R-2).
- Device listing mode: expose discovered peripherals (name, identifier, RSSI) for `--list` (FR-1.2; the flag itself is SPEC-06).

## Non-goals
UI of any kind. Polar PMD service (stretch, §13). Multi-central coordination beyond documenting R-6.

## Acceptance criteria
- On the owner's Mac with a Polar H10: launch → connected and streaming within a few seconds, unattended (§11).
- Strap taken out of range mid-session: state goes `connected → reconnecting → connected` without restart; backoff intervals observably grow.
- Bluetooth off / permission denied produce their dedicated states, not a hang or crash.
- The TUI built in SPEC-04/05 runs unmodified against this source — the `HeartRateSource` abstraction holds (§4).

## Test plan
Unit: state-machine transition table covered with a scripted fake `CBCentralManager` seam; backoff sequence values. Manual (hardware): the acceptance walk-through above, run with `--verbose` diagnostics. CI excludes hardware paths by design (NFR-6).

## Dependencies
SPEC-01 (protocol, models), SPEC-02 (parser).

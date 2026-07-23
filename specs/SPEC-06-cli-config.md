# SPEC-06 — CLI & config

## Goal
The complete command-line surface and persistent configuration: flags per PRD §7.6, the JSON config file, and preferred-device memory.

## References
PRD §7.6, FR-1.2, FR-1.3, FR-1.4, §7.4 (FR-4.1…4.3), §7.5, D-02, D-08, NFR-7.

## Scope
- swift-argument-parser surface exactly per §7.6: bare `nabz`, `--list`, `--device <name|uuid>`, `--simulate`, `--max-hr <n>`, `--no-color`, `--verbose`.
- `--list`: prints discovered sensors (name, identifier, RSSI) and exits (FR-1.2), using the SPEC-03 listing mode.
- Config file per D-08: `Codable` JSON at `~/.config/nabz/config.json` holding preferred device, HRmax, zone-threshold overrides (FR-4.3). Created lazily; malformed config → clear error, not a crash.
- Preferred-device memory: last successfully connected sensor saved and preferred on next launch (FR-1.4); `--device` overrides without overwriting until it connects.
- HRmax resolution order (D-02): `--max-hr` > config > Tanaka auto-fill (if age configured) > placeholder 190, with the active value shown in the status line — never gate first run.
- `--verbose` wiring to NFR-7 logging; `--no-color` wiring to the SPEC-04 styling path.

## Non-goals
New rendering or BLE behavior — this spec only wires surfaces to existing capabilities.

## Acceptance criteria
- Every §7.6 invocation works as documented; `nabz --help` reads cleanly.
- Second launch after a successful connection auto-prefers the remembered sensor (FR-1.4).
- Zone thresholds and HRmax overrides visibly change zone boundaries; resolution order matches D-02.
- Deleted, empty, and corrupt config files all produce sane behavior (defaults or a clear message).

## Test plan
Unit: config round-trip (encode/decode), HRmax resolution-order matrix, corrupt-config handling. Manual: the flag walk-through above with hardware and with `--simulate`.

## Dependencies
SPEC-03 (device listing, connection), SPEC-05 (full UI the flags act on).

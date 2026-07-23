# Nabz — Project Guide

Nabz (نبض, "pulse") is a native macOS app that connects to a BLE heart-rate monitor (Polar H10) and shows the live heartbeat. Phase 1 is a terminal TUI; later phases add a SwiftUI app and menu-bar/floating readouts, all on one UI-agnostic core.

## Doc map
- [Nabz-PRD.md](./Nabz-PRD.md) — requirements (FR/NFR-IDs), design language (§7b), decisions (D-NN, §14).
- [ROADMAP.md](./ROADMAP.md) — phase overview and the **spec execution order** (simulation-first).
- [specs/](./specs/) — one `SPEC-NN-name.md` per implementation session.

## Spec-driven workflow
- Each session implements **exactly one spec**, in roadmap order. Read the spec and its PRD references before writing code.
- Stay inside the spec's Scope; its Non-goals are binding. Acceptance criteria + test plan define done.
- New decisions made during a session get a `D-NN` entry in PRD §14; specs reference decisions by ID.

## Architecture rule (the one that matters)
`NabzCore` is UI-agnostic and reused verbatim by every phase. If a UI change forces a core edit, the abstraction is leaking — stop and fix the boundary (PRD §4, §6).

## Conventions
- Swift 6 strict concurrency, SPM, swift-testing.
- UI/visual decisions defer to PRD **§7b**, which is canonical over the `mockup/` images.
- `--simulate` is the default dev loop — no hardware needed for anything except SPEC-03's acceptance run.
- TUI owns stdout; diagnostics go through `os.Logger` / `--verbose` (NFR-7).

## Commands (valid once SPEC-01 lands)
```bash
swift build
swift test
swift run nabz --simulate
```

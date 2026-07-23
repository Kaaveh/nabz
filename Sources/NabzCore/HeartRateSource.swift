import Foundation
import os

/// Shared diagnostics channel (NFR-7). The TUI owns stdout; core logs go here,
/// mirrored to stderr by `--verbose` in a later spec.
public let nabzLog = Logger(subsystem: "app.nabz.core", category: "core")

/// UI-agnostic source of heart-rate data (PRD §5, §6). Every presentation runs
/// against this, so `SimulatedHeartRateSource` and `BLEHeartRateSource` (SPEC-03)
/// are interchangeable. Streams buffer `.bufferingNewest(1)` — consumers always
/// render the latest sample and never build a backlog.
public protocol HeartRateSource: Sendable {
    var samples: AsyncStream<HeartRateSample> { get }
    var connectionState: AsyncStream<ConnectionState> { get }
}

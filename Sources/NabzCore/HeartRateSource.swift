import Foundation
import os

/// Shared diagnostics channel (NFR-7). The TUI owns stdout; everything else logs here.
private let osLog = Logger(subsystem: "app.nabz.core", category: "core")

/// Set once by `--verbose` at startup, before any source or task exists, then only read.
// ponytail: write-once-at-launch global; a proper handle-injection if logging ever needs per-run config.
public nonisolated(unsafe) var nabzVerbose = false

/// Log a diagnostic through `os.Logger` (NFR-7) and, when `--verbose`, mirror it to stderr so a
/// user can `nabz --verbose 2>log` while the TUI owns stdout. Plain-`String` message, so call
/// sites format their own values (`String(format:)`) instead of `OSLogInterpolation` specifiers.
public func nabzLog(_ message: @autoclosure () -> String, level: OSLogType = .info) {
    let m = message()
    osLog.log(level: level, "\(m, privacy: .public)")
    if nabzVerbose { FileHandle.standardError.write(Data((m + "\n").utf8)) }
}

/// UI-agnostic source of heart-rate data (PRD §5, §6). Every presentation runs
/// against this, so `SimulatedHeartRateSource` and `BLEHeartRateSource` (SPEC-03)
/// are interchangeable. Streams buffer `.bufferingNewest(1)` — consumers always
/// render the latest sample and never build a backlog.
public protocol HeartRateSource: Sendable {
    var samples: AsyncStream<HeartRateSample> { get }
    var connectionState: AsyncStream<ConnectionState> { get }
}

import Foundation

/// A sensor seen while scanning, for `--list` (FR-1.2). A Sendable snapshot with no
/// CoreBluetooth types, so device discovery can be surfaced without leaking `CBPeripheral`.
public struct DiscoveredDevice: Sendable, Equatable {
    public let name: String
    public let identifier: String   // CBPeripheral.identifier UUID string
    public let rssi: Int

    public init(name: String, identifier: String, rssi: Int) {
        self.name = name
        self.identifier = identifier
        self.rssi = rssi
    }
}

/// The only things the CoreBluetooth delegate tells the actor. No `CBPeripheral` ever
/// crosses this boundary — that keeps the state machine pure and testable with a scripted
/// event sequence (SPEC-03 test plan), which is the `CBCentralManager` seam.
public enum BLEEvent: Sendable, Equatable {
    case scan                                 // manager ready / manual rescan
    case discovered(name: String)             // target peripheral found while scanning
    case subscribed(name: String)             // 0x2A37 notifications on — fully connected
    case connectFailed(reason: String)        // connect timeout / GATT error
    case dropped                              // link lost
    case unauthorized                         // CBManager .unauthorized
    case poweredOff                           // CBManager .poweredOff / unsupported
}

public enum BLEStateMachine {
    /// Pure transition per the PRD §9 table. Total by design: any (state, event) pair the
    /// table doesn't list is a no-op that returns `state` unchanged, so a stray or
    /// out-of-order delegate callback can never corrupt the modeled state.
    public static func transition(_ state: ConnectionState, on event: BLEEvent) -> ConnectionState {
        switch event {
        // `any → unauthorized / bluetoothOff`: a CBManager state change wins everywhere (NFR-5).
        case .unauthorized: return .unauthorized
        case .poweredOff:   return .bluetoothOff

        case .scan: return .scanning

        case .discovered(let name):
            // Only a fresh scan advances to connecting. While reconnecting, the UI stays on
            // `.reconnecting` until the link is genuinely back (FR-1.6), so discovery is a no-op.
            return state == .scanning ? .connecting(peripheral: name) : state

        case .subscribed(let name):
            switch state {
            case .connecting, .reconnecting: return .connected(peripheral: name)
            default: return state
            }

        case .connectFailed(let reason):
            if case .connecting = state { return .failed(reason: reason) }
            return state

        case .dropped:
            if case .connected = state { return .reconnecting }
            return state
        }
    }

    /// Match a discovered peripheral against the optional `--device` target (FR-1.3). No target
    /// → first sensor wins. Compares case-insensitively against both the UUID and the name.
    public static func matchesTarget(name: String?, identifier: String, target: String?) -> Bool {
        guard let target else { return true }
        if identifier.caseInsensitiveCompare(target) == .orderedSame { return true }
        if let name, name.caseInsensitiveCompare(target) == .orderedSame { return true }
        return false
    }
}

/// Exponential backoff for auto-reconnect (FR-1.6): 1 s doubling to a 30 s cap, ±20 % jitter,
/// unlimited attempts. Pure and seedable so the whole sequence is unit-testable off-hardware.
public struct Backoff: Sendable {
    public private(set) var attempt = 0
    public var base = 1.0        // seconds
    public var cap = 30.0        // seconds
    public var jitter = 0.2      // ±20 %

    public init() {}

    /// Un-jittered delay for the current attempt: `min(cap, base · 2^attempt)`.
    public var baseDelay: Double { min(cap, base * pow(2, Double(attempt))) }

    /// Next delay in seconds, then advance the attempt counter. Jitter is drawn from `rng`,
    /// which is injectable so tests get a deterministic sequence.
    public mutating func next(using rng: inout some RandomNumberGenerator) -> Double {
        let delay = baseDelay * Double.random(in: (1 - jitter)...(1 + jitter), using: &rng)
        attempt += 1
        return delay
    }

    /// Back to a 1 s base — call on a successful (re)connection.
    public mutating func reset() { attempt = 0 }
}

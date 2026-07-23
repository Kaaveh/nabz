import Foundation

/// One heart-rate notification, decoded (PRD §9).
/// `rrIntervals` is carried on every sample so beat-sync animation (Phase 1) and
/// HRV (Phase 4) both read from it with no core rework — see PRD §9 note.
public struct HeartRateSample: Sendable, Equatable {
    public let bpm: Int
    public let contact: SensorContact
    public let rrIntervals: [Double]   // seconds
    public let timestamp: Date

    public init(bpm: Int, contact: SensorContact, rrIntervals: [Double], timestamp: Date) {
        self.bpm = bpm
        self.contact = contact
        self.rrIntervals = rrIntervals
        self.timestamp = timestamp
    }
}

public enum SensorContact: Sendable, Equatable {
    case unsupported, noContact, contact
}

public enum ConnectionState: Sendable, Equatable {
    case idle
    case scanning
    case connecting(peripheral: String)
    case connected(peripheral: String)
    case reconnecting
    case failed(reason: String)
    case unauthorized
    case bluetoothOff
}

/// Heart-rate zone by %HRmax (PRD §7.4, D-07). `z1` is the *lowest training* zone;
/// BPM below 50 % HRmax is *below zones* and modeled as `nil`, never `z1` (FR-4.4).
public enum HRZone: Int, Sendable {
    case z1 = 1, z2, z3, z4, z5

    /// Default zone lower bounds in %HRmax (FR-4.2): Z1 50, Z2 60, Z3 70, Z4 80, Z5 90.
    public static let defaultThresholds = [50, 60, 70, 80, 90]

    /// Derive the zone from BPM and HRmax. Below the first threshold is *below zones* (`nil`,
    /// FR-4.4); each bound is inclusive; the top zone has no upper cap so max effort stays Z5.
    /// `thresholds` (FR-4.3) is five ascending %HRmax bounds; a malformed set yields `nil`.
    public static func forBPM(_ bpm: Int, hrMax: Int, thresholds: [Int] = defaultThresholds) -> HRZone? {
        guard hrMax > 0, thresholds.count == 5 else { return nil }
        let pct = Double(bpm) / Double(hrMax) * 100
        for i in stride(from: 4, through: 0, by: -1) where pct >= Double(thresholds[i]) {
            return HRZone(rawValue: i + 1)
        }
        return nil
    }
}

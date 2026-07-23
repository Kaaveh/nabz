import Foundation

/// Why parsing can fail on a `0x2A37` payload (FR-2.3). Callers log and skip;
/// parsing itself never traps or logs (SPEC-02: parser stays pure).
public enum HeartRateParseError: Error, Sendable, Equatable {
    case empty                       // zero-length payload
    case truncatedValue              // flags present but HR value bytes missing
    case truncatedRRIntervals        // RR flag set but bytes don't form whole UINT16s
}

/// Pure decoder for the BLE Heart Rate Measurement characteristic (`0x2A37`).
/// Bytes in, `HeartRateSample` out — no I/O, no CoreBluetooth (PRD §7.2, Appendix A).
public enum HeartRateMeasurementParser {
    public static func parse(
        _ data: Data,
        at timestamp: Date
    ) throws(HeartRateParseError) -> HeartRateSample {
        // Index by position rather than Data's own (possibly non-zero) startIndex.
        let bytes = [UInt8](data)
        guard let flags = bytes.first else { throw .empty }

        let is16Bit = flags & 0x01 != 0
        let hasEnergy = flags & 0x08 != 0
        let hasRR = flags & 0x10 != 0

        var i = 1
        let bpm: Int
        if is16Bit {
            guard i + 1 < bytes.count else { throw .truncatedValue }
            bpm = Int(bytes[i]) | Int(bytes[i + 1]) << 8   // little-endian
            i += 2
        } else {
            guard i < bytes.count else { throw .truncatedValue }
            bpm = Int(bytes[i])
            i += 1
        }

        // Energy Expended (UINT16 kJ) is skipped, not surfaced (SPEC-02 scope).
        if hasEnergy {
            guard i + 1 < bytes.count else { throw .truncatedValue }
            i += 2
        }

        var rr: [Double] = []
        if hasRR {
            let remaining = bytes.count - i
            guard remaining > 0, remaining % 2 == 0 else { throw .truncatedRRIntervals }
            while i + 1 < bytes.count {
                let raw = Int(bytes[i]) | Int(bytes[i + 1]) << 8   // 1/1024 s units
                rr.append(Double(raw) / 1024.0)
                i += 2
            }
        }

        return HeartRateSample(bpm: bpm, contact: contact(flags), rrIntervals: rr, timestamp: timestamp)
    }

    // Bits 1–2: 0/1 unsupported, 2 no-contact, 3 contact (Appendix A).
    private static func contact(_ flags: UInt8) -> SensorContact {
        switch (flags >> 1) & 0x03 {
        case 3:  return .contact
        case 2:  return .noContact
        default: return .unsupported
        }
    }
}

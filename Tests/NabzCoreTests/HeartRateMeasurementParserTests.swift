import Testing
import Foundation
@testable import NabzCore

// SPEC-02: exhaustive byte-fixture suite for the 0x2A37 parser (PRD Appendix A).
// Fixtures are hand-built so each flag combination is verified against known bytes.

private let t0 = Date(timeIntervalSince1970: 0)

private func parse(_ bytes: [UInt8]) throws -> HeartRateSample {
    try HeartRateMeasurementParser.parse(Data(bytes), at: t0)
}

// MARK: Valid payloads — flag combinations

@Test("UINT8 BPM, no contact-support flag")
func uint8Plain() throws {
    let s = try parse([0x00, 72])
    #expect(s.bpm == 72)
    #expect(s.contact == .unsupported)
    #expect(s.rrIntervals.isEmpty)
}

@Test("Sensor contact bits map to the right case",
      arguments: [(0b000 as UInt8, SensorContact.unsupported),
                  (0b010, .unsupported),   // bits 1–2 == 1
                  (0b100, .noContact),     // bits 1–2 == 2
                  (0b110, .contact)])      // bits 1–2 == 3
func contactBits(flags: UInt8, expected: SensorContact) throws {
    #expect(try parse([flags, 80]).contact == expected)
}

@Test("UINT16 BPM > 255 round-trips little-endian")
func uint16Bpm() throws {
    // 300 = 0x012C → LE bytes 0x2C, 0x01. Flag bit0 set.
    let s = try parse([0x01, 0x2C, 0x01])
    #expect(s.bpm == 300)
}

@Test("UINT16 BPM at 256 boundary")
func uint16Boundary() throws {
    #expect(try parse([0x01, 0x00, 0x01]).bpm == 256)
}

@Test("Energy Expended present is skipped, not surfaced")
func energySkipped() throws {
    // flags 0x08 (energy) + UINT8 bpm 65, then 2 energy bytes.
    let s = try parse([0x08, 65, 0xFF, 0xFF])
    #expect(s.bpm == 65)
    #expect(s.rrIntervals.isEmpty)
}

@Test("Energy present alongside RR: energy skipped, RR still parsed")
func energyThenRR() throws {
    // flags 0x18 (energy+RR), bpm 60, energy 2 bytes, one RR = 1024 → 1.0 s.
    let s = try parse([0x18, 60, 0x10, 0x27, 0x00, 0x04])
    #expect(s.bpm == 60)
    #expect(s.rrIntervals == [1.0])
}

// MARK: RR-interval conversion (1/1024 s → seconds)

@Test("RR conversion precision",
      arguments: [(1024 as UInt16, 1.0), (512, 0.5), (256, 0.25)])
func rrConversion(raw: UInt16, seconds: Double) throws {
    let s = try parse([0x10, 70, UInt8(raw & 0xFF), UInt8(raw >> 8)])
    #expect(s.rrIntervals == [seconds])
}

@Test("Multiple RR-intervals in one notification")
func multipleRR() throws {
    // flags 0x10 (RR), bpm 75, then 1024, 512, 2048 (=2.0 s).
    let s = try parse([0x10, 75, 0x00, 0x04, 0x00, 0x02, 0x00, 0x08])
    #expect(s.bpm == 75)
    #expect(s.rrIntervals == [1.0, 0.5, 2.0])
}

@Test("UINT16 BPM with contact and multiple RR together")
func everythingAtOnce() throws {
    // flags 0x11 (uint16+RR) | contact bits → 0b111 = 0x17. bpm 260, two RRs.
    let s = try parse([0x17, 0x04, 0x01, 0x00, 0x04, 0x00, 0x02])
    #expect(s.bpm == 260)
    #expect(s.contact == .contact)
    #expect(s.rrIntervals == [1.0, 0.5])
}

// MARK: Malformed payloads — never trap, always a typed error

@Test("Zero-length payload errors")
func emptyPayload() {
    #expect(throws: HeartRateParseError.empty) { try parse([]) }
}

@Test("Flags-only (1 byte) errors: no HR value")
func flagsOnly() {
    #expect(throws: HeartRateParseError.truncatedValue) { try parse([0x00]) }
}

@Test("UINT16 flag but only one value byte errors")
func truncatedUint16() {
    #expect(throws: HeartRateParseError.truncatedValue) { try parse([0x01, 0x2C]) }
}

@Test("Energy flag but missing energy bytes errors")
func truncatedEnergy() {
    #expect(throws: HeartRateParseError.truncatedValue) { try parse([0x08, 65, 0xFF]) }
}

@Test("RR flag but zero RR bytes errors")
func rrFlagNoBytes() {
    #expect(throws: HeartRateParseError.truncatedRRIntervals) { try parse([0x10, 70]) }
}

@Test("RR flag with odd trailing byte errors")
func truncatedRR() {
    #expect(throws: HeartRateParseError.truncatedRRIntervals) { try parse([0x10, 70, 0x00, 0x04, 0x00]) }
}

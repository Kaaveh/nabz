import Testing
import Foundation
@testable import NabzCore

// MARK: Zone boundaries (PRD §7.4, FR-4.2/4.4)

@Test("Below 50 % HRmax is below-zones (nil), never Z1", arguments: [0, 49, 94])
func belowZones(bpm: Int) {
    // hrMax 190: 50 % = 95 bpm, so 94 and below are below-zones.
    #expect(HRZone.forBPM(bpm, hrMax: 190) == nil)
}

@Test("Boundaries are lower-bound inclusive across all zones")
func boundaries() {
    // hrMax 200 → each 10 % is a round 20 bpm, so edges land exactly.
    #expect(HRZone.forBPM(99,  hrMax: 200) == nil)   // 49.5 %
    #expect(HRZone.forBPM(100, hrMax: 200) == .z1)   // 50 %
    #expect(HRZone.forBPM(119, hrMax: 200) == .z1)   // 59.5 %
    #expect(HRZone.forBPM(120, hrMax: 200) == .z2)   // 60 %
    #expect(HRZone.forBPM(140, hrMax: 200) == .z3)   // 70 %
    #expect(HRZone.forBPM(160, hrMax: 200) == .z4)   // 80 %
    #expect(HRZone.forBPM(180, hrMax: 200) == .z5)   // 90 %
}

@Test("Z5 has no upper cap — at and above HRmax stays Z5")
func z5UpperEdge() {
    #expect(HRZone.forBPM(200, hrMax: 200) == .z5)   // 100 %
    #expect(HRZone.forBPM(230, hrMax: 200) == .z5)   // 115 %
}

@Test("Non-positive HRmax yields no zone rather than dividing by zero")
func guardHRMax() {
    #expect(HRZone.forBPM(120, hrMax: 0) == nil)
}

// MARK: Seeded simulator determinism

@Test("Same seed reproduces the same BPM/RR sequence")
func seededDeterminism() {
    var a = HeartRateSimulator(seed: 42)
    var b = HeartRateSimulator(seed: 42)
    let now = Date(timeIntervalSince1970: 0)
    for _ in 0..<50 {
        let sa = a.next(now: now), sb = b.next(now: now)
        #expect(sa.bpm == sb.bpm)
        #expect(sa.rrIntervals == sb.rrIntervals)
    }
}

@Test("Different seeds diverge (not accidentally constant)")
func differentSeedsDiverge() {
    var a = HeartRateSimulator(seed: 1)
    var b = HeartRateSimulator(seed: 2)
    let now = Date(timeIntervalSince1970: 0)
    let seqA = (0..<50).map { _ in a.next(now: now).bpm }
    let seqB = (0..<50).map { _ in b.next(now: now).bpm }
    #expect(seqA != seqB)
}

@Test("Simulated samples stay in a plausible band with contact and RR present")
func plausibleOutput() {
    var sim = HeartRateSimulator(seed: 7)
    for _ in 0..<200 {
        let s = sim.next()
        #expect((55...160).contains(s.bpm))
        #expect(s.contact == .contact)
        #expect(!s.rrIntervals.isEmpty)
        #expect(s.rrIntervals.allSatisfy { $0 > 0 })
    }
}

// MARK: Stream delivers latest-value semantics (bufferingNewest(1))

@Test("A slow consumer sees only the newest buffered sample")
func latestValueSemantics() async {
    var cont: AsyncStream<HeartRateSample>.Continuation!
    let stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
    let s = { (bpm: Int) in HeartRateSample(bpm: bpm, contact: .contact, rrIntervals: [], timestamp: Date()) }
    cont.yield(s(60))
    cont.yield(s(61))
    cont.yield(s(62))   // only this survives the 1-slot buffer
    cont.finish()

    let got = await stream.reduce(into: [Int]()) { $0.append($1.bpm) }
    #expect(got == [62])
}

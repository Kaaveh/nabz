import Testing
import Foundation
@testable import NabzTUI
@testable import NabzCore

private func sample(bpm: Int, rr: [Double], at t: Date) -> HeartRateSample {
    HeartRateSample(bpm: bpm, contact: .contact, rrIntervals: rr, timestamp: t)
}

// MARK: Beat scheduler (RR present / absent / irregular) — FR-3.1, R-3

@Test("A beat fires once its scheduled RR-interval elapses, not before")
func rrScheduledBeat() {
    let t0 = Date()
    var anim = HeartAnimation()
    anim.ingest(sample(bpm: 60, rr: [1.0], at: t0), now: t0)

    anim.advance(now: t0.addingTimeInterval(0.5))
    #expect(anim.contraction(now: t0.addingTimeInterval(0.5)) == 0)   // beat at +1.0s hasn't fired

    anim.advance(now: t0.addingTimeInterval(1.01))
    #expect(anim.contraction(now: t0.addingTimeInterval(1.01)) > 0)   // now it has
}

@Test("Absent RR falls back to BPM-derived cadence (R-3)")
func bpmFallbackCadence() {
    let t0 = Date()
    var anim = HeartAnimation()
    anim.ingest(sample(bpm: 120, rr: [], at: t0), now: t0)   // 120 bpm → 0.5s interval

    anim.advance(now: t0.addingTimeInterval(0.4))
    #expect(anim.contraction(now: t0.addingTimeInterval(0.4)) == 0)
    anim.advance(now: t0.addingTimeInterval(0.51))
    #expect(anim.contraction(now: t0.addingTimeInterval(0.51)) > 0)
}

@Test("Irregular RR produces irregularly spaced beat peaks")
func irregularRR() {
    let t0 = Date()
    var anim = HeartAnimation()
    anim.ingest(sample(bpm: 75, rr: [0.4, 1.2], at: t0), now: t0)   // beats at +0.4 and +1.6

    anim.advance(now: t0.addingTimeInterval(0.52))                  // +0.12 past the first beat
    #expect(anim.contraction(now: t0.addingTimeInterval(0.52)) > 0.99)   // first beat at its peak

    anim.advance(now: t0.addingTimeInterval(1.5))                  // deep in the 1.2 s gap
    #expect(anim.contraction(now: t0.addingTimeInterval(1.5)) < 0.2)     // released, no beat yet

    anim.advance(now: t0.addingTimeInterval(1.72))                 // +0.12 past the second beat
    #expect(anim.contraction(now: t0.addingTimeInterval(1.72)) > 0.99)   // second beat at its peak
}

// MARK: Contraction envelope — §7b motion

@Test("Contraction rises through systole then eases back to rest")
func contractionEnvelope() {
    #expect(beatContraction(phase: 0, interval: 1.0) == 0)
    #expect(beatContraction(phase: 0.06, interval: 1.0) > 0.4)   // mid-systole rising
    #expect(beatContraction(phase: 0.12, interval: 1.0) == 1)    // peak at ~120 ms
    let mid = beatContraction(phase: 0.5, interval: 1.0)
    #expect(mid > 0 && mid < 1)                                  // diastole release
    #expect(beatContraction(phase: 1.0, interval: 1.0) == 0)     // rest by the next beat
}

// MARK: BPM tween (D-03)

@Test("Displayed BPM eases toward the new sample over ~300 ms, never snaps")
func bpmTween() {
    let t0 = Date()
    var anim = HeartAnimation()
    anim.ingest(sample(bpm: 70, rr: [0.85], at: t0), now: t0)
    #expect(anim.displayedBPM(now: t0) == 70)   // first reading lands immediately, no glide from 0

    anim.ingest(sample(bpm: 100, rr: [0.6], at: t0.addingTimeInterval(1)), now: t0.addingTimeInterval(1))
    let atStart = anim.displayedBPM(now: t0.addingTimeInterval(1))
    let mid = anim.displayedBPM(now: t0.addingTimeInterval(1.15))
    let end = anim.displayedBPM(now: t0.addingTimeInterval(1.4))
    #expect(abs(atStart - 70) < 0.5)      // starts from the old value
    #expect(mid > 70 && mid < 100)        // glides through the middle
    #expect(abs(end - 100) < 0.5)         // settles on the target after ~300 ms
}

// MARK: Rolling window (D-03)

@Test("Window keeps only the last 60 s of samples")
func windowTrim() {
    let t0 = Date()
    var anim = HeartAnimation()
    anim.ingest(sample(bpm: 60, rr: [1.0], at: t0), now: t0)                       // old
    anim.ingest(sample(bpm: 80, rr: [0.75], at: t0.addingTimeInterval(59)), now: t0.addingTimeInterval(59))
    anim.advance(now: t0.addingTimeInterval(59))                                    // 60s window: both kept
    #expect(anim.frame(now: t0.addingTimeInterval(59)).window.count == 2)

    anim.advance(now: t0.addingTimeInterval(61))                                    // first now > 60s old
    #expect(anim.frame(now: t0.addingTimeInterval(61)).window.map(\.bpm) == [80])
}

// MARK: Zone → color, including below-zone (FR-4.4, D-07)

@Test("Zone maps to its palette color; below-zone maps to neutral, never Z1")
func zoneColors() {
    #expect(Palette.forZone(.z1) == Palette.z1)
    #expect(Palette.forZone(.z5) == Palette.z5)
    #expect(Palette.forZone(nil) == Palette.belowZones)
    #expect(Palette.forZone(nil) != Palette.z1)   // FR-4.4: below-zone is not Z1
}

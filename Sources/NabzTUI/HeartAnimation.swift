import Foundation
import NabzCore

/// Contraction envelope, 0 (rest) … 1 (peak systole). Fast systole (~120 ms) then an eased
/// diastole release that finishes right as the next beat lands (§7b motion). `phase` = seconds
/// since the last beat; `interval` = expected beat-to-beat time so the release fills the gap.
/// Shared by the live scheduler and the idle pulse, so both move on the same curve.
func beatContraction(phase: Double, interval: Double) -> Double {
    let systole = 0.12
    guard phase >= 0 else { return 0 }
    if phase < systole { return phase / systole }         // rise to peak over ~120 ms
    let release = max(0.2, interval - systole)
    let p = min(1, (phase - systole) / release)
    return max(0, (1 - p) * (1 - p))                       // ease-out fall back to rest
}

/// The animation values the renderer draws for one frame — a pure snapshot, so the renderer
/// stays a function of its inputs and the timing math is unit-testable without a terminal.
public struct HeartFrame: Sendable, Equatable {
    public let contraction: Double        // 0 rest … 1 peak systole
    public let displayedBPM: Double       // eased toward each new sample (D-03); 0 = no reading
    public let window: [HeartRateSample]  // last 60 s, newest last — for the sparkline
    public init(contraction: Double, displayedBPM: Double, window: [HeartRateSample]) {
        self.contraction = contraction; self.displayedBPM = displayedBPM; self.window = window
    }
    public static let empty = HeartFrame(contraction: 0, displayedBPM: 0, window: [])
}

/// Beat scheduler + BPM tween + rolling window, advanced by the run loop each frame. Kept out
/// of the renderer (which is pure per frame) because these accumulate across frames. Beats are
/// scheduled from RR-intervals with a BPM-derived fallback (R-3, FR-3.1); the BPM number eases
/// toward each sample (D-03); the window holds 60 s of raw samples for the sparkline.
public struct HeartAnimation: Sendable {
    public static let windowSeconds: TimeInterval = 60   // D-03

    private var scheduled: [Date] = []          // future beat times, sorted
    private var lastBeat: Date?                 // most recent fired beat
    private var interval: TimeInterval = 60.0 / 70   // current cadence, for diastole easing
    private var window: [HeartRateSample] = []
    private var tweenFrom = 0.0, tweenTo = 0.0
    private var tweenStart: Date?

    public init() {}

    /// Take a fresh live sample: lay its beats forward (RR-synced, BPM fallback), retarget the
    /// BPM tween, and append to the rolling window. Irregular RR → irregular beat spacing, by
    /// construction. Call this once per new sample (the run loop de-dupes by timestamp).
    public mutating func ingest(_ s: HeartRateSample, now: Date = Date()) {
        let rr = s.rrIntervals.isEmpty ? [60.0 / Double(max(1, s.bpm))] : s.rrIntervals
        var t = max(now, scheduled.last ?? now)
        if t.timeIntervalSince(now) > 2 { scheduled.removeAll(); t = now }   // no runaway backlog
        for r in rr { t = t.addingTimeInterval(r); scheduled.append(t) }
        interval = rr.last!

        let current = displayedBPM(now: now)
        tweenFrom = current == 0 ? Double(s.bpm) : current   // first reading: no glide from 0
        tweenTo = Double(s.bpm)
        tweenStart = now

        window.append(s)
    }

    /// Fire any beats now due and trim the window to the last 60 s. Called every frame.
    public mutating func advance(now: Date = Date()) {
        while let first = scheduled.first, first <= now {
            lastBeat = first
            scheduled.removeFirst()
        }
        let cutoff = now.addingTimeInterval(-Self.windowSeconds)
        window.removeAll { $0.timestamp < cutoff }
    }

    public func frame(now: Date = Date()) -> HeartFrame {
        HeartFrame(contraction: contraction(now: now),
                   displayedBPM: displayedBPM(now: now),
                   window: window)
    }

    func contraction(now: Date) -> Double {
        guard let lastBeat else { return 0 }   // honest: no fake beat before the first fires
        return beatContraction(phase: now.timeIntervalSince(lastBeat), interval: interval)
    }

    func displayedBPM(now: Date) -> Double {
        guard let tweenStart else { return tweenTo }
        let p = min(1, max(0, now.timeIntervalSince(tweenStart) / 0.3))   // ~300 ms, D-03
        let eased = 1 - (1 - p) * (1 - p)                                 // ease-out
        return tweenFrom + (tweenTo - tweenFrom) * eased
    }
}

import Foundation

/// Deterministic PRNG (SplitMix64) so a seeded simulator is reproducible for tests.
/// The stdlib's `SystemRandomNumberGenerator` isn't seedable, hence this ~10 lines.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Pure sample generator: BPM random-walk within a plausible band and RR-intervals
/// derived from the current BPM with small jitter (FR-5.2). Seeded → reproducible.
/// Separated from timing so tests exercise it without waiting on the clock.
public struct HeartRateSimulator: Sendable {
    private var rng: SeededGenerator
    private var bpm: Double

    public init(seed: UInt64? = nil) {
        // No seed → draw one from system entropy, so default runs are randomized.
        rng = SeededGenerator(seed: seed ?? UInt64.random(in: .min ... .max))
        bpm = 70
    }

    /// Advance one notification's worth of data. `now` is injectable for tests;
    /// production passes the real clock so latency can be instrumented (§11).
    public mutating func next(now: Date = Date()) -> HeartRateSample {
        bpm = min(160, max(55, bpm + Double.random(in: -3...3, using: &rng)))
        let beats = max(1, Int((bpm / 60).rounded()))
        let rr = (0..<beats).map { _ in
            (60.0 / bpm) * Double.random(in: 0.95...1.05, using: &rng)
        }
        return HeartRateSample(bpm: Int(bpm.rounded()), contact: .contact,
                               rrIntervals: rr, timestamp: now)
    }
}

/// `HeartRateSource` backed by the simulator — the strap-free default dev loop
/// (FR-5.1). Pumps a sample every `interval` on a background task.
public final class SimulatedHeartRateSource: HeartRateSource {
    public let samples: AsyncStream<HeartRateSample>
    public let connectionState: AsyncStream<ConnectionState>
    private let pump: Task<Void, Never>

    public init(seed: UInt64? = nil, interval: Duration = .seconds(1)) {
        var sampleCont: AsyncStream<HeartRateSample>.Continuation!
        samples = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { sampleCont = $0 }
        var stateCont: AsyncStream<ConnectionState>.Continuation!
        connectionState = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { stateCont = $0 }
        let samplesOut = sampleCont!, stateOut = stateCont!

        pump = Task {
            stateOut.yield(.connected(peripheral: "Simulator"))
            var sim = HeartRateSimulator(seed: seed)
            while !Task.isCancelled {
                samplesOut.yield(sim.next())
                try? await Task.sleep(for: interval)
            }
            samplesOut.finish()
            stateOut.finish()
        }
    }

    deinit { pump.cancel() }
}

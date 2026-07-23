import Foundation
import NabzCore

/// SPEC-01 executable stub: stream the simulated source as plain text (no flags,
/// no TUI yet — SPEC-04/06). Ctrl-C exits the process cleanly.
@main
struct Nabz {
    static let hrMax = 190  // placeholder default, D-02

    static func main() async {
        // Line-buffer stdout so streamed lines flush immediately when piped/redirected
        // (default is block-buffered off a tty, which would swallow output on SIGINT).
        setvbuf(stdout, nil, _IOLBF, 0)
        let source = SimulatedHeartRateSource()
        for await s in source.samples {
            let zone = HRZone.forBPM(s.bpm, hrMax: hrMax).map { "Z\($0.rawValue)" } ?? "—"
            let rr = s.rrIntervals.map { String(format: "%.3f", $0) }.joined(separator: ",")
            print("bpm=\(s.bpm)  zone=\(zone)  rr=[\(rr)]")
        }
    }
}

import Foundation
import NabzCore
import NabzTUI

/// SPEC-04 executable: run the full-screen TUI against the simulated source (no flags yet —
/// `--simulate`/`--max-hr`/`--no-color` wiring is SPEC-06). Quit with `q`, Ctrl-C, or SIGTERM;
/// the terminal is always restored on the way out.
@main
struct Nabz {
    static let hrMax = 190  // placeholder default, D-02

    static func main() async {
        await runTUI(source: SimulatedHeartRateSource(), hrMax: hrMax)
    }
}

import ArgumentParser
import Foundation
import NabzCore
import NabzTUI

/// The full CLI surface (PRD §7.6). This target only *wires* flags to capabilities that already
/// exist in the core and TUI — no new rendering or BLE behavior (SPEC-06 non-goal). HRmax, zone
/// thresholds, and device memory resolve in `NabzCore.Config`; the TUI just consumes the result.
@main
struct Nabz: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nabz",
        abstract: "Live heart-rate monitor for a BLE sensor (Polar H10)."
    )

    @Flag(name: .long, help: "List discoverable HR sensors and exit.")
    var list = false

    @Option(name: .long, help: "Connect to this sensor by name or UUID.")
    var device: String?

    @Flag(name: .long, help: "Run against a simulated heart-rate source (no hardware).")
    var simulate = false

    @Option(name: .customLong("max-hr"), help: "HRmax for zone calculation (overrides config).")
    var maxHR: Int?

    @Flag(name: .customLong("no-color"), help: "Disable coloring.")
    var noColor = false

    @Flag(name: .long, help: "Mirror diagnostics to stderr (NFR-7).")
    var verbose = false

    mutating func run() async {
        nabzVerbose = verbose

        if list {
            let devices = await BLEHeartRateSource.discover()
            if devices.isEmpty { print("No HR sensors found.") }
            for d in devices { print("\(d.name)  \(d.identifier)  \(d.rssi) dBm") }
            return
        }

        let config = Config.loadOrDefault()
        let hrMax = config.resolveMaxHR(cli: maxHR)
        let mode = ColorMode.detect(noColor: noColor)
        let thresholds = config.thresholds

        if simulate {
            await runTUI(source: SimulatedHeartRateSource(), hrMax: hrMax, mode: mode, zoneThresholds: thresholds)
            return
        }

        // `--device` overrides the remembered sensor but doesn't persist until it connects (FR-1.4);
        // whatever we actually connect to gets saved for next launch.
        let source = BLEHeartRateSource(target: device ?? config.preferredDevice)
        let base = config
        await runTUI(source: source, hrMax: hrMax, mode: mode, zoneThresholds: thresholds) { name in
            guard base.preferredDevice != name else { return }
            var updated = base
            updated.preferredDevice = name
            try? updated.save()
        }
    }
}

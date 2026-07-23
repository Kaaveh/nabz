import Testing
import Foundation
@testable import NabzTUI
@testable import NabzCore

private func rowText(_ buf: ScreenBuffer, _ row: Int) -> String {
    String((0..<buf.cols).map { buf[row, $0].ch })
}

private func render(_ state: ConnectionState, contact: SensorContact = .contact, bpm: Int = 72) -> ScreenBuffer {
    var buf = ScreenBuffer(cols: 80, rows: 24)
    let sample = HeartRateSample(bpm: bpm, contact: contact, rrIntervals: [0.83], timestamp: Date())
    Renderer.paint(into: &buf, input: FrameInput(state: state, sample: sample, elapsed: 65, hrMax: 190))
    return buf
}

// MARK: DisplayState mapping (FR-3.6)

@Test("No-contact is derived from a live connection, not a connection state of its own")
func noContactDerivation() {
    #expect(DisplayState.from(.connected(peripheral: "H10"), contact: .noContact) == .noContact)
    #expect(DisplayState.from(.connected(peripheral: "H10"), contact: .contact) == .live)
    #expect(DisplayState.from(.reconnecting, contact: nil) == .reconnecting)
    #expect(DisplayState.from(.unauthorized, contact: nil) == .alert)
    #expect(DisplayState.from(.bluetoothOff, contact: nil) == .alert)
    #expect(DisplayState.from(.idle, contact: nil) == .scanning)
}

// MARK: Each state renders a distinct, correct status line (§7b state visuals)

@Test("Every connection state produces a distinct status line")
func statesAreDistinct() {
    let states: [ConnectionState] = [
        .scanning, .connecting(peripheral: "Polar H10"), .connected(peripheral: "Polar H10"),
        .reconnecting, .failed(reason: "timeout"), .unauthorized, .bluetoothOff,
    ]
    let lines = Set(states.map { rowText(render($0), 23).trimmingCharacters(in: .whitespaces) })
    #expect(lines.count == states.count)   // all seven are visually different
}

@Test("Permission states carry actionable fix copy (R-1)")
func actionableCopy() {
    #expect(rowText(render(.unauthorized), 23).contains("System Settings"))
    #expect(rowText(render(.bluetoothOff), 23).contains("Bluetooth is off"))
}

@Test("Status line shows sensor name, contact, elapsed, and active HRmax (FR-3.5, D-02)")
func statusLineContents() {
    let line = rowText(render(.connected(peripheral: "Polar H10"), contact: .contact), 23)
    #expect(line.contains("Polar H10"))
    #expect(line.contains("contact"))
    #expect(line.contains("01:05"))       // elapsed 65s
    #expect(line.contains("HRmax 190"))
}

@Test("No-contact status warns to adjust the strap")
func noContactCopy() {
    #expect(rowText(render(.connected(peripheral: "H10"), contact: .noContact), 23).contains("adjust the strap"))
}

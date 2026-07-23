import Testing
import Foundation
@testable import NabzCore

// MARK: ConnectionState transition table (PRD §9)

@Test("idle → scanning on launch/rescan")
func idleToScanning() {
    #expect(BLEStateMachine.transition(.idle, on: .scan) == .scanning)
}

@Test("scanning → connecting when the target is discovered")
func scanningToConnecting() {
    #expect(BLEStateMachine.transition(.scanning, on: .discovered(name: "H10"))
            == .connecting(peripheral: "H10"))
}

@Test("connecting → connected once the HR characteristic is subscribed")
func connectingToConnected() {
    #expect(BLEStateMachine.transition(.connecting(peripheral: "H10"), on: .subscribed(name: "H10"))
            == .connected(peripheral: "H10"))
}

@Test("connecting → failed on timeout / GATT error")
func connectingToFailed() {
    #expect(BLEStateMachine.transition(.connecting(peripheral: "H10"), on: .connectFailed(reason: "boom"))
            == .failed(reason: "boom"))
}

@Test("connected → reconnecting when the link drops")
func connectedToReconnecting() {
    #expect(BLEStateMachine.transition(.connected(peripheral: "H10"), on: .dropped) == .reconnecting)
}

@Test("reconnecting → connected when a backoff attempt subscribes")
func reconnectingToConnected() {
    #expect(BLEStateMachine.transition(.reconnecting, on: .subscribed(name: "H10"))
            == .connected(peripheral: "H10"))
}

@Test("reconnecting stays reconnecting through discovery until actually connected (FR-1.6)")
func reconnectingHoldsThroughDiscovery() {
    #expect(BLEStateMachine.transition(.reconnecting, on: .discovered(name: "H10")) == .reconnecting)
}

@Test("any state → unauthorized / bluetoothOff on a CBManager change (NFR-5)",
      arguments: [ConnectionState.idle, .scanning, .connecting(peripheral: "H10"),
                  .connected(peripheral: "H10"), .reconnecting])
func managerChangeWinsEverywhere(from: ConnectionState) {
    #expect(BLEStateMachine.transition(from, on: .unauthorized) == .unauthorized)
    #expect(BLEStateMachine.transition(from, on: .poweredOff) == .bluetoothOff)
}

@Test("Undocumented pairs are no-ops that can't corrupt state")
func straySignalsAreNoOps() {
    // A late `.dropped` while idle, or a `.subscribed` while scanning, must not transition.
    #expect(BLEStateMachine.transition(.idle, on: .dropped) == .idle)
    #expect(BLEStateMachine.transition(.scanning, on: .subscribed(name: "H10")) == .scanning)
    #expect(BLEStateMachine.transition(.connected(peripheral: "H10"),
                                       on: .connectFailed(reason: "x")) == .connected(peripheral: "H10"))
}

// MARK: Target matching (FR-1.3)

@Test("No target matches the first sensor")
func noTargetMatchesFirst() {
    #expect(BLEStateMachine.matchesTarget(name: "Polar H10", identifier: "UUID-1", target: nil))
}

@Test("Target matches by name or UUID, case-insensitively; else no match")
func targetMatching() {
    #expect(BLEStateMachine.matchesTarget(name: "Polar H10", identifier: "ABC-123", target: "polar h10"))
    #expect(BLEStateMachine.matchesTarget(name: "Polar H10", identifier: "ABC-123", target: "abc-123"))
    #expect(!BLEStateMachine.matchesTarget(name: "Polar H10", identifier: "ABC-123", target: "Wahoo"))
    #expect(!BLEStateMachine.matchesTarget(name: nil, identifier: "ABC-123", target: "Polar"))
}

// MARK: Backoff sequence (FR-1.6)

@Test("Un-jittered base doubles from 1 s and caps at 30 s")
func backoffBaseSequence() {
    var b = Backoff()
    var rng = SeededGenerator(seed: 1)
    let expectedBases = [1.0, 2, 4, 8, 16, 30, 30, 30]   // 32 → capped at 30
    for expected in expectedBases {
        #expect(b.baseDelay == expected)
        _ = b.next(using: &rng)
    }
}

@Test("Each delay stays within ±20 % of its base and retries never stop")
func backoffJitterBounds() {
    var b = Backoff()
    var rng = SeededGenerator(seed: 99)
    for _ in 0..<200 {                                   // well past the cap: infinite retries
        let base = b.baseDelay
        let delay = b.next(using: &rng)
        #expect(delay >= base * 0.8)
        #expect(delay <= base * 1.2)
    }
    #expect(b.baseDelay == 30.0)                          // still capped, still counting
}

@Test("reset() returns to the 1 s base after a successful reconnect")
func backoffReset() {
    var b = Backoff()
    var rng = SeededGenerator(seed: 7)
    for _ in 0..<5 { _ = b.next(using: &rng) }
    #expect(b.baseDelay == 30.0)
    b.reset()
    #expect(b.baseDelay == 1.0)
}

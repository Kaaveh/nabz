import Testing
import Foundation
@testable import NabzCore

/// A unique temp config path per test, cleaned up after the closure.
private func withTempConfig(_ body: (URL) throws -> Void) rethrows {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "nabz-test-\(UUID().uuidString)/config.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try body(url)
}

@Test func configRoundTrips() throws {
    try withTempConfig { url in
        let original = Config(preferredDevice: "Polar H10 1234", maxHR: 188, age: 32, zoneThresholds: [55, 65, 75, 85, 95])
        try original.save(to: url)
        #expect(try Config.load(from: url) == original)
    }
}

@Test func missingFileLoadsAsEmpty() throws {
    try withTempConfig { url in
        #expect(try Config.load(from: url) == Config())   // lazy: no file yet, not an error
    }
}

@Test func corruptFileThrowsButLoadOrDefaultRecovers() throws {
    try withTempConfig { url in
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json{".utf8).write(to: url)
        #expect(throws: (any Error).self) { try Config.load(from: url) }
        #expect(Config.loadOrDefault(from: url) == Config())   // sane fallback, no crash
    }
}

@Test func hrMaxResolutionOrder() {
    // --max-hr wins over everything.
    #expect(Config(maxHR: 180, age: 30).resolveMaxHR(cli: 200) == 200)
    // config maxHR beats age.
    #expect(Config(maxHR: 180, age: 30).resolveMaxHR(cli: nil) == 180)
    // age → Tanaka (208 − 0.7·30 = 187).
    #expect(Config(age: 30).resolveMaxHR(cli: nil) == 187)
    // nothing set → placeholder, never gates the first run.
    #expect(Config().resolveMaxHR(cli: nil) == 190)
}

@Test func thresholdsFallBackWhenMalformed() {
    #expect(Config().thresholds == HRZone.defaultThresholds)                 // unset
    #expect(Config(zoneThresholds: [50, 60, 70]).thresholds == HRZone.defaultThresholds)      // wrong count
    #expect(Config(zoneThresholds: [90, 80, 70, 60, 50]).thresholds == HRZone.defaultThresholds) // descending
    #expect(Config(zoneThresholds: [55, 65, 75, 85, 95]).thresholds == [55, 65, 75, 85, 95])  // valid override
}

@Test func zoneThresholdOverrideShiftsBoundaries() {
    // With bounds raised to 55…, 54% HRmax is below zones where the default would call it Z1.
    let custom = [55, 65, 75, 85, 95]
    #expect(HRZone.forBPM(108, hrMax: 200) == .z1)                       // 54% default → Z1
    #expect(HRZone.forBPM(108, hrMax: 200, thresholds: custom) == nil)  // 54% custom → below zones
    #expect(HRZone.forBPM(110, hrMax: 200, thresholds: custom) == .z1)  // 55% custom → Z1
}

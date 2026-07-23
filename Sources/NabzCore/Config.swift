import Foundation

/// Persistent preferences (D-08): one inspectable `Codable` JSON file at
/// `~/.config/nabz/config.json` — no UserDefaults, no dependencies. Every field is optional so a
/// partial or empty file is valid; resolution against CLI flags and defaults happens here, not in
/// the UI, so the rules (D-02 HRmax order, FR-4.3 thresholds) are unit-testable.
public struct Config: Codable, Sendable, Equatable {
    public var preferredDevice: String?    // last sensor we connected to (FR-1.4)
    public var maxHR: Int?                  // explicit HRmax (FR-4.1)
    public var age: Int?                    // for Tanaka auto-fill when maxHR is absent (D-02)
    public var zoneThresholds: [Int]?       // five ascending %HRmax bounds (FR-4.3)

    public init(preferredDevice: String? = nil, maxHR: Int? = nil,
                age: Int? = nil, zoneThresholds: [Int]? = nil) {
        self.preferredDevice = preferredDevice
        self.maxHR = maxHR
        self.age = age
        self.zoneThresholds = zoneThresholds
    }

    /// HRmax to use, most-specific wins (D-02): `--max-hr` > config > Tanaka(age) > placeholder.
    /// Never gates the first run — a bare launch always resolves to 190.
    public func resolveMaxHR(cli: Int?) -> Int {
        if let cli { return cli }
        if let maxHR { return maxHR }
        if let age { return Int((208.0 - 0.7 * Double(age)).rounded()) }  // Tanaka, D-02
        return 190                                                        // placeholder, D-02
    }

    /// Validated zone thresholds (FR-4.3): the config's five ascending bounds, or the defaults if
    /// absent or malformed — so a bad override degrades to standard zones instead of breaking them.
    public var thresholds: [Int] {
        guard let z = zoneThresholds, z.count == 5, z == z.sorted() else { return HRZone.defaultThresholds }
        return z
    }

    // MARK: Persistence

    /// Honors `$HOME` (unlike `homeDirectoryForCurrentUser`, which ignores it on macOS) so the
    /// path follows a shell's home override and is testable with a temp `HOME`.
    public static var defaultPath: URL {
        let home = ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: ".config/nabz/config.json")
    }

    /// Load the config, or an empty one if the file doesn't exist yet (created lazily on first save).
    /// Throws on a present-but-unreadable/malformed file so callers can surface a clear message.
    public static func load(from url: URL = defaultPath) throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
    }

    /// Load, or fall back to defaults with a clear stderr message on a corrupt file — never crash
    /// (acceptance: deleted/empty/corrupt all behave sanely). We don't rewrite the bad file here, so
    /// the user can fix it; it's only overwritten if a later successful connection saves a device.
    public static func loadOrDefault(from url: URL = defaultPath) -> Config {
        do { return try load(from: url) }
        catch {
            FileHandle.standardError.write(Data("nabz: ignoring unreadable config at \(url.path): \(error.localizedDescription)\n".utf8))
            return Config()
        }
    }

    public func save(to url: URL = Config.defaultPath) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

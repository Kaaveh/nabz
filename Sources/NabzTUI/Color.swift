import Foundation
import NabzCore

/// How color escapes are emitted. Truecolor with a 256-color fallback, detected via
/// `$COLORTERM`; `.none` renders no color at all — the `--no-color` / dumb-terminal path
/// where state is carried entirely by text (FR-3.7, R-4, §7b accessibility).
public enum ColorMode: Sendable, Equatable {
    case truecolor, ansi256, none

    /// Detect from the environment. `noColor` (the SPEC-06 `--no-color` flag) forces `.none`.
    public static func detect(
        noColor: Bool = false,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> ColorMode {
        if noColor { return .none }
        let term = env["TERM"] ?? ""
        if term.isEmpty || term == "dumb" { return .none }
        let colorterm = (env["COLORTERM"] ?? "").lowercased()
        if colorterm.contains("truecolor") || colorterm.contains("24bit") { return .truecolor }
        return .ansi256
    }
}

/// A palette color with both a truecolor RGB and its 256-color index (§7b canonical table),
/// so one value renders correctly in every `ColorMode`.
public struct Color: Sendable, Equatable {
    public let r, g, b: UInt8
    public let xterm: Int

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, xterm: Int) {
        self.r = r; self.g = g; self.b = b; self.xterm = xterm
    }

    /// SGR fragment setting this as the foreground, e.g. `;38;2;R;G;B`. Empty in `.none`.
    func sgrForeground(_ mode: ColorMode) -> String {
        switch mode {
        case .truecolor: return ";38;2;\(r);\(g);\(b)"
        case .ansi256:   return ";38;5;\(xterm)"
        case .none:      return ""
        }
    }
}

/// The canonical §7b zone palette — single source of truth shared with SPEC-05's zone
/// coloring. SPEC-04 only uses `belowZones` (dim heart), `z3` (no-contact warning), and
/// `z5` (error accent); the rest are here so both specs agree on the values.
public enum Palette {
    public static let belowZones = Color(0x9C, 0xA3, 0xAF, xterm: 248)
    public static let z1 = Color(0x3B, 0x82, 0xF6, xterm: 33)
    public static let z2 = Color(0x22, 0xC5, 0x5E, xterm: 41)
    public static let z3 = Color(0xEA, 0xB3, 0x08, xterm: 178)
    public static let z4 = Color(0xF9, 0x73, 0x16, xterm: 208)
    public static let z5 = Color(0xEF, 0x44, 0x44, xterm: 203)

    /// Color for a zone, or the neutral below-zones gray for `nil` (FR-4.4, D-07) — the one
    /// place SPEC-05's heart, BPM number, sparkline, and legend agree on zone→color.
    public static func forZone(_ z: HRZone?) -> Color {
        switch z {
        case .z1: return z1
        case .z2: return z2
        case .z3: return z3
        case .z4: return z4
        case .z5: return z5
        case nil: return belowZones
        }
    }
}

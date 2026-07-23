import Foundation
import NabzCore

/// Everything the renderer needs for one frame. Assembled by the run loop from the latest
/// stream values; the renderer itself is a pure function of this, so it's inspectable in tests.
public struct FrameInput: Sendable, Equatable {
    public let state: ConnectionState
    public let sample: HeartRateSample?
    public let elapsed: TimeInterval
    public let hrMax: Int
    public init(state: ConnectionState, sample: HeartRateSample?, elapsed: TimeInterval, hrMax: Int) {
        self.state = state; self.sample = sample; self.elapsed = elapsed; self.hrMax = hrMax
    }
}

/// The visual state actually drawn (§7b state-visuals table). Distinct from `ConnectionState`
/// because *no contact* isn't a connection state — it's a live connection whose sensor reports
/// no skin contact (FR-3.6). One place decides the mapping so every region stays consistent.
enum DisplayState: Equatable {
    case scanning, connecting, live, noContact, reconnecting, alert

    static func from(_ state: ConnectionState, contact: SensorContact?) -> DisplayState {
        switch state {
        case .idle, .scanning:        return .scanning
        case .connecting:             return .connecting
        case .connected:              return contact == .noContact ? .noContact : .live
        case .reconnecting:           return .reconnecting
        case .failed, .unauthorized, .bluetoothOff: return .alert
        }
    }
}

/// Paints a full frame: the beat-synced dot-matrix heart, the eased block-glyph BPM number,
/// zone-colored per §7b, the rolling sparkline, the zone legend with the active zone
/// highlighted, and the status line. Pure per frame — animation timing is baked into `heart`.
public enum Renderer {
    // Two heart frames, rest → peak. Contraction swaps to the smaller (contracted) shape and
    // brightens it, so each beat reads as a squeeze (§7b dot-matrix brand mark).
    private static let heartRest = [
        "  ███   ███  ",
        " ███████████ ",
        " ███████████ ",
        "  █████████  ",
        "   ███████   ",
        "    █████    ",
        "     ███     ",
        "      █      ",
    ]
    private static let heartPeak = [
        "             ",
        "   ██   ██   ",
        "  █████████  ",
        "   ███████   ",
        "    █████    ",
        "     ███     ",
        "      █      ",
        "             ",
    ]

    // 5-row block digits (§7b: block-glyph BPM, ~5–7 rows). `—` = no reading.
    private static let digits: [Character: [String]] = [
        "0": ["███", "█ █", "█ █", "█ █", "███"],
        "1": [" █ ", "██ ", " █ ", " █ ", "███"],
        "2": ["███", "  █", "███", "█  ", "███"],
        "3": ["███", "  █", "███", "  █", "███"],
        "4": ["█ █", "█ █", "███", "  █", "  █"],
        "5": ["███", "█  ", "███", "  █", "███"],
        "6": ["███", "█  ", "███", "█ █", "███"],
        "7": ["███", "  █", "  █", "  █", "  █"],
        "8": ["███", "█ █", "███", "█ █", "███"],
        "9": ["███", "█ █", "███", "  █", "███"],
        "—": ["   ", "   ", "███", "   ", "   "],
    ]

    // 8-level partial blocks for the sparkline bars.
    private static let bars: [Character] = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    /// Colors are carried in each cell's `Style` and resolved to the terminal's `ColorMode`
    /// later, at diff time — so painting is mode-agnostic.
    public static func paint(into buf: inout ScreenBuffer, input: FrameInput, heart: HeartFrame = .empty) {
        let layout = Layout.forSize(cols: buf.cols, rows: buf.rows)
        let display = DisplayState.from(input.state, contact: input.sample?.contact)
        let zone = input.sample.flatMap { HRZone.forBPM($0.bpm, hrMax: input.hrMax) }

        paintHero(into: &buf, rect: layout.hero, input: input, display: display, zone: zone, heart: heart)
        if let spark = layout.sparkline { paintSparkline(into: &buf, rect: spark, input: input, display: display, heart: heart) }
        if let legend = layout.legend { paintLegend(into: &buf, rect: legend, display: display, zone: zone) }
        paintStatus(into: &buf, rect: layout.status, input: input, display: display, zone: zone)
    }

    // MARK: Hero — heart (left) + BPM (right)

    private static func paintHero(
        into buf: inout ScreenBuffer, rect: Rect,
        input: FrameInput, display: DisplayState, zone: HRZone?, heart: HeartFrame
    ) {
        guard rect.h > 0 else { return }   // no room (1-row terminal) → status line only

        // Contraction source: the live scheduler when live; the honest dimmed idle pulse
        // (§7b — "stale data never fakes life") otherwise; no pulse for alert states.
        let contraction: Double
        switch display {
        case .live:                                     contraction = heart.contraction
        case .scanning, .connecting, .reconnecting, .noContact:
                                                        contraction = idleContraction(input.elapsed)
        case .alert:                                    contraction = 0
        }

        let heartColor: Color
        switch display {
        case .live:      heartColor = Palette.forZone(zone)
        case .noContact: heartColor = Palette.z3
        case .alert:     heartColor = Palette.z5
        default:         heartColor = Palette.belowZones
        }
        let dim = display != .live
        let heartStyle = Style(fg: heartColor, dim: dim, bold: display == .live && contraction > 0.55)

        // Heart left half, BPM right half.
        let half = max(1, rect.w / 2)
        let art = contraction > 0.5 ? heartPeak : heartRest
        let heartTop = rect.y + max(0, (rect.h - art.count) / 2)
        for (i, line) in art.enumerated() where heartTop + i < rect.y + rect.h {
            buf.putCentered(line, row: heartTop + i, x: rect.x, width: half, style: heartStyle)
        }

        paintBPM(into: &buf, rect: Rect(x: rect.x + half, y: rect.y, w: rect.w - half, h: rect.h),
                 input: input, display: display, zone: zone, heart: heart)
    }

    /// Big block-glyph BPM number, tweened (D-03). The value shown is the eased `displayedBPM`,
    /// falling back to the raw sample before the tween has a reading.
    private static func paintBPM(
        into buf: inout ScreenBuffer, rect: Rect,
        input: FrameInput, display: DisplayState, zone: HRZone?, heart: HeartFrame
    ) {
        let value: Int?
        switch display {
        case .live, .noContact:
            let eased = Int(heart.displayedBPM.rounded())
            value = eased > 0 ? eased : input.sample?.bpm
        case .reconnecting: value = input.sample?.bpm     // last value, grayed
        default:            value = nil                    // dash
        }

        let color: Color
        switch display {
        case .live:      color = Palette.forZone(zone)
        case .noContact: color = Palette.z3
        default:         color = Palette.belowZones
        }
        let style = Style(fg: color, dim: display != .live, bold: display == .live)

        let rows = bigNumber(value)
        let top = rect.y + max(0, (rect.h - rows.count - 1) / 2)   // +1 for the "BPM" label
        for (i, line) in rows.enumerated() where top + i < rect.y + rect.h {
            buf.putCentered(line, row: top + i, x: rect.x, width: rect.w, style: style)
        }
        let labelRow = top + rows.count
        if labelRow < rect.y + rect.h {
            buf.putCentered("BPM", row: labelRow, x: rect.x, width: rect.w,
                            style: Style(fg: Palette.belowZones, dim: true))
        }
    }

    /// Render an integer (or `—`) as rows of block glyphs.
    private static func bigNumber(_ value: Int?) -> [String] {
        let text = value.map(String.init) ?? "—"
        var rows = [String](repeating: "", count: 5)
        for (i, ch) in text.enumerated() {
            let glyph = digits[ch] ?? digits["—"]!
            for r in 0..<5 { rows[r] += (i == 0 ? "" : " ") + glyph[r] }
        }
        return rows
    }

    // MARK: Sparkline — 60 s rolling window, zone-colored per sample (FR-3.3, D-03)

    private static func paintSparkline(
        into buf: inout ScreenBuffer, rect: Rect,
        input: FrameInput, display: DisplayState, heart: HeartFrame
    ) {
        guard rect.h > 0, display == .live || display == .noContact else { return }
        let visible = Array(heart.window.suffix(rect.w))   // one column per sample, newest at right
        guard !visible.isEmpty else { return }

        let bpms = visible.map(\.bpm)
        let lo = bpms.min()!, hi = bpms.max()!
        let span = max(10, hi - lo)                        // floor so a flat line doesn't jitter
        let low = Double(lo + hi) / 2 - Double(span) / 2
        let maxLevel = rect.h * 8
        let firstCol = rect.x + rect.w - visible.count      // right-align

        for (i, s) in visible.enumerated() {
            let norm = min(1, max(0, (Double(s.bpm) - low) / Double(span)))
            let level = Int((norm * Double(maxLevel)).rounded())
            let color = Palette.forZone(HRZone.forBPM(s.bpm, hrMax: input.hrMax))
            let col = firstCol + i
            for row in 0..<rect.h {
                let cellLevel = level - (rect.h - 1 - row) * 8   // bottom row is the fullest
                let ch: Character = cellLevel >= 8 ? "█" : cellLevel <= 0 ? " " : bars[cellLevel]
                if ch != " " { buf[rect.y + row, col] = Cell(ch: ch, style: Style(fg: color)) }
            }
        }
    }

    // MARK: Legend — zone names, active zone highlighted (§7b accessibility)

    private static func paintLegend(into buf: inout ScreenBuffer, rect: Rect, display: DisplayState, zone: HRZone?) {
        let labels = ["Z1", "Z2", "Z3", "Z4", "Z5"]
        let width = labels.count * 4 - 2      // "Zn" + two-space gaps
        var col = rect.x + max(0, (rect.w - width) / 2)
        for (i, label) in labels.enumerated() {
            let z = HRZone(rawValue: i + 1)
            let active = display == .live && zone == z
            let style = Style(fg: Palette.forZone(z), dim: !active, bold: active)
            buf.put(label, row: rect.y, col: col, style: style)
            col += 4
        }
    }

    // MARK: Status line — state, sensor, contact, elapsed, HRmax, active zone (FR-3.5, D-02)

    private static func paintStatus(
        into buf: inout ScreenBuffer, rect: Rect,
        input: FrameInput, display: DisplayState, zone: HRZone?
    ) {
        let accent: Style
        switch display {
        case .alert:     accent = Style(fg: Palette.z5)
        case .noContact: accent = Style(fg: Palette.z3)
        default:         accent = Style(fg: Palette.belowZones, dim: true)
        }

        var parts: [String] = [message(for: input.state, display: display)]
        if let name = sensorName(input.state) { parts.append(name) }
        parts.append(contactIndicator(input.sample?.contact))
        if display == .live { parts.append(zoneName(zone)) }   // name the zone in text, not color alone
        parts.append(elapsed(input.elapsed))
        parts.append("HRmax \(input.hrMax)")

        let line = parts.joined(separator: "  ·  ")
        buf.put(line, row: rect.y, col: rect.x, style: accent)
    }

    private static func zoneName(_ zone: HRZone?) -> String {
        zone.map { "Z\($0.rawValue)" } ?? "Below zones"
    }

    /// One-line copy per state; the permission states carry the actionable fix (R-1, §7b).
    private static func message(for state: ConnectionState, display: DisplayState) -> String {
        switch state {
        case .idle, .scanning:        return "Scanning for sensors…"
        case .connecting(let name):   return "Connecting to \(name)…"
        case .connected:              return display == .noContact ? "No skin contact — adjust the strap" : "Live"
        case .reconnecting:           return "Reconnecting…"
        case .failed(let reason):     return "Error: \(reason)"
        case .unauthorized:
            return "Bluetooth permission denied — grant it in System Settings › Privacy & Security › Bluetooth"
        case .bluetoothOff:
            return "Bluetooth is off — turn it on in Control Center or System Settings"
        }
    }

    private static func sensorName(_ state: ConnectionState) -> String? {
        switch state {
        case .connecting(let name), .connected(let name): return name
        default: return nil
        }
    }

    private static func contactIndicator(_ contact: SensorContact?) -> String {
        switch contact {
        case .contact:      return "● contact"
        case .noContact:    return "○ no contact"
        case .unsupported:  return "— contact n/a"
        case nil:           return "— contact n/a"
        }
    }

    private static func elapsed(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// Dimmed fixed-cadence idle pulse (~48 bpm) — an honest "not your pulse" beat (§7b).
    private static func idleContraction(_ elapsed: Double) -> Double {
        let interval = 1.25
        return beatContraction(phase: elapsed.truncatingRemainder(dividingBy: interval), interval: interval)
    }
}

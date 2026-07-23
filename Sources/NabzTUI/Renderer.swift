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

/// Paints a state-driven frame. No heart *animation*, sparkline, or zone coloring — those are
/// SPEC-05; this draws a static placeholder heart, the BPM number, a status line, and (when the
/// layout allows) a zone legend and an empty sparkline band. Each state is visually distinct.
public enum Renderer {
    // Static placeholder heart (SPEC-05 replaces this with the beat-synced dot-matrix hero).
    private static let heart = [
        " ▁▁   ▁▁ ",
        "▐  ▚ ▞  ▌",
        " ▚     ▞ ",
        "  ▚   ▞  ",
        "   ▚ ▞   ",
        "    ▝    ",
    ]

    /// Colors are carried in each cell's `Style` and resolved to the terminal's `ColorMode`
    /// later, at diff time — so painting is mode-agnostic.
    public static func paint(into buf: inout ScreenBuffer, input: FrameInput) {
        let layout = Layout.forSize(cols: buf.cols, rows: buf.rows)
        let display = DisplayState.from(input.state, contact: input.sample?.contact)

        paintHero(into: &buf, rect: layout.hero, input: input, display: display)
        if let legend = layout.legend { paintLegend(into: &buf, rect: legend) }
        paintStatus(into: &buf, rect: layout.status, input: input, display: display)
        // Sparkline band is reserved by the layout but intentionally left blank until SPEC-05.
    }

    // MARK: Hero — heart (left) + BPM (right)

    private static func paintHero(
        into buf: inout ScreenBuffer, rect: Rect,
        input: FrameInput, display: DisplayState
    ) {
        guard rect.h > 0 else { return }   // no room (1-row terminal) → status line only
        let heartStyle: Style
        switch display {
        case .live:        heartStyle = Style()                               // default fg (zone color is SPEC-05)
        case .noContact:   heartStyle = Style(fg: Palette.z3)                 // hollow/warning yellow
        case .alert:       heartStyle = Style(fg: Palette.z5)                 // red accent
        default:           heartStyle = Style(fg: Palette.belowZones, dim: true)  // idle/dimmed
        }

        // Heart occupies the left half; BPM the right half.
        let half = max(1, rect.w / 2)
        let heartW = heart.map(\.count).max() ?? 0
        let heartTop = rect.y + max(0, (rect.h - heart.count) / 2)
        for (i, line) in heart.enumerated() where heartTop + i < rect.y + rect.h {
            buf.putCentered(line, row: heartTop + i, x: rect.x, width: min(half, max(heartW, half)), style: heartStyle)
        }

        // BPM: shown only when a live-ish state has a reading; otherwise a neutral dash.
        let bpmText: String
        switch display {
        case .live, .noContact:            bpmText = input.sample.map { "\($0.bpm)" } ?? "—"
        case .reconnecting:                bpmText = input.sample.map { "\($0.bpm)" } ?? "—"  // last value, grayed
        default:                           bpmText = "—"
        }
        let bpmStyle: Style = display == .reconnecting
            ? Style(fg: Palette.belowZones, dim: true)   // last BPM grayed (§7b)
            : heartStyle
        let bpmRow = rect.y + rect.h / 2
        buf.putCentered(bpmText, row: bpmRow, x: rect.x + half, width: rect.w - half, style: bpmStyle)
        buf.putCentered("BPM", row: min(rect.y + rect.h - 1, bpmRow + 1),
                        x: rect.x + half, width: rect.w - half,
                        style: Style(fg: Palette.belowZones, dim: true))
    }

    // MARK: Legend — zone names (SPEC-05 colors + active highlight)

    private static func paintLegend(into buf: inout ScreenBuffer, rect: Rect) {
        let text = "Z1  Z2  Z3  Z4  Z5"
        buf.putCentered(text, row: rect.y, x: rect.x, width: rect.w,
                        style: Style(fg: Palette.belowZones, dim: true))
    }

    // MARK: Status line — state, sensor, contact, elapsed, HRmax (FR-3.5, D-02)

    private static func paintStatus(
        into buf: inout ScreenBuffer, rect: Rect,
        input: FrameInput, display: DisplayState
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
        parts.append(elapsed(input.elapsed))
        parts.append("HRmax \(input.hrMax)")

        let line = parts.joined(separator: "  ·  ")
        buf.put(line, row: rect.y, col: rect.x, style: accent)
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
}

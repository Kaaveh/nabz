import Foundation

/// Per-cell styling. Only what SPEC-04 needs: a foreground color (nil = terminal default)
/// plus dim/bold attributes used by the state visuals (§7b).
public struct Style: Sendable, Equatable {
    public var fg: Color?
    public var dim: Bool
    public var bold: Bool
    public init(fg: Color? = nil, dim: Bool = false, bold: Bool = false) {
        self.fg = fg; self.dim = dim; self.bold = bold
    }

    /// Full SGR: reset then re-apply, so switching to this style never inherits leftovers.
    func sgr(_ mode: ColorMode) -> String {
        var s = "\u{1B}[0"
        if bold { s += ";1" }
        if dim { s += ";2" }
        if let fg { s += fg.sgrForeground(mode) }
        return s + "m"
    }
}

public struct Cell: Sendable, Equatable {
    public var ch: Character
    public var style: Style
    public init(ch: Character = " ", style: Style = Style()) {
        self.ch = ch; self.style = style
    }
}

/// A fixed grid of styled cells and a diff to the terminal. The diff (NFR-2) emits ANSI only
/// for cells that changed versus the previous frame, grouping contiguous same-row runs to
/// minimize cursor moves. Pure and value-typed, so the diff logic is unit-testable.
public struct ScreenBuffer: Sendable, Equatable {
    public let cols: Int
    public let rows: Int
    private var cells: [Cell]

    public init(cols: Int, rows: Int) {
        self.cols = max(0, cols)
        self.rows = max(0, rows)
        cells = Array(repeating: Cell(), count: self.cols * self.rows)
    }

    private func inBounds(_ row: Int, _ col: Int) -> Bool {
        row >= 0 && row < rows && col >= 0 && col < cols
    }

    public subscript(row: Int, col: Int) -> Cell {
        get { cells[row * cols + col] }
        set { if inBounds(row, col) { cells[row * cols + col] = newValue } }
    }

    /// Write `text` starting at (row, col), clipped to the row's right edge. One line only —
    /// callers place multi-row content line by line. Never splits a glyph across the edge.
    public mutating func put(_ text: String, row: Int, col: Int, style: Style = Style()) {
        guard row >= 0, row < rows else { return }
        var c = col
        for ch in text {
            guard c >= 0 else { c += 1; continue }
            guard c < cols else { break }
            cells[row * cols + c] = Cell(ch: ch, style: style)
            c += 1
        }
    }

    /// Centered `put` within `[x, x+width)` on `row`; over-long text is left-anchored+clipped.
    public mutating func putCentered(_ text: String, row: Int, x: Int, width: Int, style: Style = Style()) {
        let pad = max(0, (width - text.count) / 2)
        put(text, row: row, col: x + pad, style: style)
    }

    /// ANSI transforming a screen showing `previous` into one showing `self`. Mismatched
    /// dimensions fall back to a full repaint against a blank buffer of the current size
    /// (the caller clears the screen on resize, so `previous` is blank then anyway).
    public func diff(from previous: ScreenBuffer, mode: ColorMode) -> String {
        guard previous.cols == cols, previous.rows == rows else {
            return diff(from: ScreenBuffer(cols: cols, rows: rows), mode: mode)
        }
        var out = ""
        var current: Style? = nil   // last SGR emitted; nil = unknown/default
        for r in 0..<rows {
            var c = 0
            while c < cols {
                let i = r * cols + c
                if cells[i] == previous.cells[i] { c += 1; continue }
                out += "\u{1B}[\(r + 1);\(c + 1)H"          // 1-based cursor move
                while c < cols, cells[r * cols + c] != previous.cells[r * cols + c] {
                    let cell = cells[r * cols + c]
                    if current != cell.style {
                        out += cell.style.sgr(mode)
                        current = cell.style
                    }
                    out.append(cell.ch)
                    c += 1
                }
            }
        }
        if current != nil { out += "\u{1B}[0m" }
        return out
    }
}

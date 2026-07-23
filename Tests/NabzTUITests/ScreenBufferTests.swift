import Testing
@testable import NabzTUI

// MARK: ANSI diff logic (NFR-2)

@Test("Identical frames produce no output")
func noChangeNoOutput() {
    let a = ScreenBuffer(cols: 10, rows: 3)
    #expect(a.diff(from: a, mode: .none) == "")
}

@Test("Only changed cells are emitted, positioned 1-based")
func emitsChangedRun() {
    let blank = ScreenBuffer(cols: 10, rows: 3)
    var next = blank
    next.put("hi", row: 1, col: 2, style: Style())
    let out = next.diff(from: blank, mode: .none)
    #expect(out.contains("\u{1B}[2;3H"))   // row 2, col 3 (1-based)
    #expect(out.contains("hi"))
    // Nothing from the untouched rows.
    #expect(!out.contains("\u{1B}[1;"))
    #expect(!out.contains("\u{1B}[3;"))
}

@Test("A contiguous run gets a single cursor move, not one per cell")
func runsCoalesce() {
    let blank = ScreenBuffer(cols: 10, rows: 1)
    var next = blank
    next.put("abcd", row: 0, col: 0)
    let out = next.diff(from: blank, mode: .none)
    let moves = out.components(separatedBy: "H").count - 1
    #expect(moves == 1)
}

@Test("Reverting a cell to blank emits a space to erase it")
func erasesToBlank() {
    let blank = ScreenBuffer(cols: 5, rows: 1)
    var shown = blank
    shown.put("X", row: 0, col: 0)
    // Going from `shown` back to blank must overwrite the X with a space.
    let out = blank.diff(from: shown, mode: .none)
    #expect(out.contains(" "))
    #expect(!out.contains("X"))
}

@Test("Mismatched dimensions fall back to a full repaint from blank")
func resizeRepaints() {
    let small = ScreenBuffer(cols: 4, rows: 1)
    var big = ScreenBuffer(cols: 8, rows: 2)
    big.put("Z", row: 0, col: 0)
    let out = big.diff(from: small, mode: .none)
    #expect(out.contains("Z"))   // did not crash on size mismatch; painted content
}

@Test("Truecolor emits an RGB SGR; .none emits no color")
func colorModes() {
    let blank = ScreenBuffer(cols: 4, rows: 1)
    var next = blank
    next.put("x", row: 0, col: 0, style: Style(fg: Palette.z5))
    #expect(next.diff(from: blank, mode: .truecolor).contains("38;2;239;68;68"))
    #expect(next.diff(from: blank, mode: .ansi256).contains("38;5;203"))
    #expect(!next.diff(from: blank, mode: .none).contains("38;"))
}

// MARK: Color-mode detection (FR-3.7, R-4)

@Test("COLORTERM=truecolor wins; TERM=dumb/empty disables color; --no-color forces off")
func detectColorMode() {
    #expect(ColorMode.detect(env: ["TERM": "xterm-256color", "COLORTERM": "truecolor"]) == .truecolor)
    #expect(ColorMode.detect(env: ["TERM": "xterm-256color"]) == .ansi256)
    #expect(ColorMode.detect(env: ["TERM": "dumb"]) == .none)
    #expect(ColorMode.detect(env: [:]) == .none)
    #expect(ColorMode.detect(noColor: true, env: ["COLORTERM": "truecolor"]) == .none)
}

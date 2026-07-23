import Foundation

public struct Rect: Sendable, Equatable {
    public let x, y, w, h: Int
    public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
}

/// Where each region lives for a given terminal size, and which optional regions survive
/// (§7b). Hero (heart + BPM) and the status line are always present; the sparkline and zone
/// legend drop as the terminal shrinks, in the §7b degradation order: legend first, then
/// sparkline. Pure function of size, so the breakpoint/degradation math is unit-testable.
public struct Layout: Sendable, Equatable {
    public let cols, rows: Int
    public let hero: Rect
    public let sparkline: Rect?   // SPEC-05 fills it; SPEC-04 only reserves the band
    public let legend: Rect?
    public let status: Rect

    /// Full UI needs 80×24 (§7b minimum). Below that, degrade: drop legend, then sparkline.
    public static func forSize(cols rawCols: Int, rows rawRows: Int) -> Layout {
        let cols = max(1, rawCols)
        let rows = max(1, rawRows)

        let showSparkline = cols >= 60 && rows >= 16
        let showLegend = cols >= 80 && rows >= 24   // legend implies sparkline (60×16 ⊂ 80×24)

        // Fill from the bottom up: status, then legend, then the sparkline band.
        let status = Rect(x: 0, y: rows - 1, w: cols, h: 1)
        var top = rows - 1   // first row still available to the regions above the status line

        var legend: Rect? = nil
        if showLegend, top >= 1 {
            top -= 1
            legend = Rect(x: 0, y: top, w: cols, h: 1)
        }

        var sparkline: Rect? = nil
        if showSparkline, top >= 4 {          // 3-row band, and leave ≥1 row for the hero
            let h = 3
            top -= h
            sparkline = Rect(x: 0, y: top, w: cols, h: h)
        }

        let hero = Rect(x: 0, y: 0, w: cols, h: max(1, top))
        return Layout(cols: cols, rows: rows, hero: hero, sparkline: sparkline, legend: legend, status: status)
    }
}

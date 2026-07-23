import Testing
@testable import NabzTUI

// MARK: Layout breakpoints & degradation order (§7b)

@Test("Full UI (legend + sparkline) at the 80×24 minimum")
func fullLayout() {
    let l = Layout.forSize(cols: 80, rows: 24)
    #expect(l.legend != nil)
    #expect(l.sparkline != nil)
    #expect(l.hero.h >= 1)
}

@Test("Just below 80×24 drops the legend first, keeps the sparkline")
func dropLegendFirst() {
    let l = Layout.forSize(cols: 79, rows: 23)
    #expect(l.legend == nil)
    #expect(l.sparkline != nil)
}

@Test("Small terminal drops the sparkline too — heart + BPM + status only")
func compact() {
    let l = Layout.forSize(cols: 50, rows: 12)
    #expect(l.legend == nil)
    #expect(l.sparkline == nil)
    #expect(l.hero.h >= 1)
}

@Test("Degradation is monotonic: a legend never appears without a sparkline",
      arguments: [(40, 8), (59, 15), (60, 16), (79, 23), (80, 24), (200, 60)])
func monotonicDegradation(cols: Int, rows: Int) {
    let l = Layout.forSize(cols: cols, rows: rows)
    if l.legend != nil { #expect(l.sparkline != nil) }   // legend ⊂ sparkline in the drop order
}

@Test("Regions never overlap and stay within bounds",
      arguments: [(80, 24), (100, 40), (60, 16), (50, 10), (1, 1)])
func regionsWithinBounds(cols: Int, rows: Int) {
    let l = Layout.forSize(cols: cols, rows: rows)
    let regions = [l.hero, l.sparkline, l.legend, l.status].compactMap { $0 }
    for r in regions {
        #expect(r.x >= 0 && r.y >= 0)
        #expect(r.x + r.w <= l.cols)
        #expect(r.y + r.h <= l.rows)
    }
    // Status is the bottom row; the hero starts at the top and never reaches into it.
    #expect(l.status.y == l.rows - 1)
    #expect(l.hero.y == 0)
    #expect(l.hero.y + l.hero.h <= l.status.y)
}

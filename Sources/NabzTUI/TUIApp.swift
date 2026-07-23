import Foundation
import Darwin
import NabzCore

// Set by the key-reading thread on 'q'; polled by the loop for a graceful quit. (Ctrl-C and
// SIGTERM don't route through here — they're handled by the signal path in Terminal.swift.)
private nonisolated(unsafe) var quitRequested: sig_atomic_t = 0

/// Latest stream values, isolated so the two ingest tasks and the render loop don't race
/// (Swift 6 strict concurrency; `Mutex` needs macOS 15, our floor is 13).
private actor Model {
    private var state: ConnectionState = .idle
    private var sample: HeartRateSample?
    func setState(_ s: ConnectionState) { state = s }
    func setSample(_ s: HeartRateSample) { sample = s }
    func snapshot() -> (ConnectionState, HeartRateSample?) { (state, sample) }
}

/// Run the full-screen TUI against any `HeartRateSource` until the user quits (`q`, Ctrl-C, or
/// SIGTERM). A steady ~30 fps `Task.sleep` loop drives diff-based redraws without busy-spinning
/// (NFR-2/3). `NABZ_SMOKE_FRAMES=N` renders N frames then exits cleanly — the NFR-6 CI smoke run.
public func runTUI(source: HeartRateSource, hrMax: Int, mode: ColorMode = ColorMode.detect()) async {
    let terminal = Terminal()
    let smokeFrames = ProcessInfo.processInfo.environment["NABZ_SMOKE_FRAMES"].flatMap(Int.init)

    terminal.enter()
    defer { terminal.leave() }

    let model = Model()
    let stateTask = Task { for await s in source.connectionState { await model.setState(s) } }
    let sampleTask = Task { for await s in source.samples { await model.setSample(s) } }
    defer { stateTask.cancel(); sampleTask.cancel() }

    if terminal.isTTY { startKeyReader() }

    let start = Date()
    var (cols, rows) = terminal.size
    var previous = ScreenBuffer(cols: cols, rows: rows)
    var frame = 0

    while quitRequested == 0 {
        if terminal.consumeResize() {
            (cols, rows) = terminal.size
            previous = ScreenBuffer(cols: cols, rows: rows)
            terminal.write("\u{1B}[2J")   // clear once; next diff repaints from blank
        }

        let (state, sample) = await model.snapshot()
        var buf = ScreenBuffer(cols: cols, rows: rows)
        let input = FrameInput(state: state, sample: sample, elapsed: Date().timeIntervalSince(start), hrMax: hrMax)
        Renderer.paint(into: &buf, input: input)
        terminal.write(buf.diff(from: previous, mode: mode))
        previous = buf

        frame += 1
        if let n = smokeFrames, frame >= n { break }
        try? await Task.sleep(for: .milliseconds(33))   // ~30 fps, no busy-spin
    }
}

/// Blocking one-byte reads on a dedicated thread (raw mode → a key per read), so the
/// cooperative pool is never blocked. Only 'q'/'Q' is handled; Ctrl-C stays a signal.
private func startKeyReader() {
    Thread.detachNewThread {
        var byte: UInt8 = 0
        while Darwin.read(STDIN_FILENO, &byte, 1) == 1 {
            if byte == UInt8(ascii: "q") || byte == UInt8(ascii: "Q") { quitRequested = 1; break }
        }
    }
}

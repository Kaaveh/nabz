import Foundation
import Darwin

// MARK: - Process-wide terminal restore (async-signal-safe)
//
// A signal handler may run at any instant, including mid-redraw, and can only call
// async-signal-safe functions (`tcsetattr`, `write`, `raise`). It reads these globals — never
// the Swift `Terminal` object — so restoring the terminal from SIGINT/SIGTERM/crash is safe.
// This is the "single teardown path reachable from every exit" (FR-1.7, NFR-4).

private nonisolated(unsafe) var savedTermios = termios()
private nonisolated(unsafe) var termiosSaved = false
private nonisolated(unsafe) var resizePending: sig_atomic_t = 0

// Show cursor, leave alternate screen buffer, reset SGR. Written verbatim by the handler.
private let restoreSequence = "\u{1B}[?25h\u{1B}[?1049l\u{1B}[0m"

/// The one restore, callable from a signal handler or `atexit`. Idempotent by construction.
private func restoreTerminal() {
    if termiosSaved { tcsetattr(STDIN_FILENO, TCSANOW, &savedTermios) }
    _ = restoreSequence.withCString { Darwin.write(STDOUT_FILENO, $0, strlen($0)) }
}

// Non-capturing top-level funcs convert to C function pointers for `signal`/`atexit`.
private func onTerminatingSignal(_ sig: Int32) {
    restoreTerminal()
    signal(sig, SIG_DFL)   // restore default and re-raise so exit status reflects the signal
    raise(sig)
}
private func onWinch(_ sig: Int32) { resizePending = 1 }
private func atexitRestore() { restoreTerminal() }

/// Owns the terminal for the TUI's lifetime: raw-ish input, alternate screen buffer, hidden
/// cursor, resize signalling, and teardown. `enter()`/`leave()` bracket the run loop.
public final class Terminal {
    public private(set) var isTTY: Bool
    private var entered = false

    public init() { isTTY = isatty(STDOUT_FILENO) != 0 && isatty(STDIN_FILENO) != 0 }

    /// Terminal size via `ioctl`; falls back to 80×24 off a tty (CI/pipes) so rendering still works.
    public var size: (cols: Int, rows: Int) {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0, ws.ws_col > 0, ws.ws_row > 0 {
            return (Int(ws.ws_col), Int(ws.ws_row))
        }
        return (80, 24)
    }

    /// True once since the last call — the loop polls this to relayout on SIGWINCH.
    public func consumeResize() -> Bool {
        if resizePending != 0 { resizePending = 0; return true }
        return false
    }

    public func write(_ s: String) {
        var s = s
        s.withUTF8 { buf in _ = Darwin.write(STDOUT_FILENO, buf.baseAddress, buf.count) }
    }

    /// Enter raw-ish mode + alternate buffer and install every teardown hook. Off a tty
    /// (CI smoke run) we skip raw mode and signal-driven input but still install `atexit`.
    public func enter() {
        guard !entered else { return }
        entered = true
        atexit(atexitRestore)   // best-effort restore on an uncaught normal exit

        if isTTY {
            var raw = termios()
            tcgetattr(STDIN_FILENO, &raw)
            savedTermios = raw
            termiosSaved = true
            // Disable canonical mode + echo, keep ISIG so Ctrl-C/Ctrl-\ still raise signals
            // (our handler restores the terminal). One byte per read, blocking.
            raw.c_lflag &= ~UInt(ICANON | ECHO)
            raw.c_cc.16 = 1  // VMIN
            raw.c_cc.17 = 0  // VTIME
            tcsetattr(STDIN_FILENO, TCSANOW, &raw)

            for sig in [SIGINT, SIGTERM, SIGSEGV, SIGABRT] { signal(sig, onTerminatingSignal) }
            signal(SIGWINCH, onWinch)
        }

        // Alt buffer, hide cursor, clear. Harmless if written to a pipe.
        write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[2J")
    }

    /// The normal-quit teardown. Idempotent; the signal path calls `restoreTerminal` directly.
    public func leave() {
        guard entered else { return }
        entered = false
        restoreTerminal()
        termiosSaved = false
    }
}

import Foundation
import ContainerKit

// ctui — a live terminal dashboard for `container`.
//
//   ↑/↓ or j/k   move        s   start / stop        l   follow logs
//   r            refresh     x   remove              q   quit
//
// Renders a container table that auto-refreshes, driven by ContainerKit.

// MARK: - ANSI helpers

enum Ansi {
    static let esc = "\u{1B}["
    static let clear = "\(esc)2J\(esc)H"
    static let home = "\(esc)H"
    static let hideCursor = "\(esc)?25l"
    static let showCursor = "\(esc)?25h"
    static let altOn = "\u{1B}[?1049h"
    static let altOff = "\u{1B}[?1049l"
    static let reset = "\(esc)0m"
    static let bold = "\(esc)1m"
    static let dim = "\(esc)2m"
    static let rev = "\(esc)7m"
    static func fg(_ n: Int) -> String { "\(esc)38;5;\(n)m" }
    static func clearLine() -> String { "\(esc)2K" }
}

func out(_ s: String) { FileHandle.standardOutput.write(Data(s.utf8)) }

// MARK: - Raw terminal mode

final class RawMode {
    private var original = termios()
    func enable() {
        tcgetattr(STDIN_FILENO, &original)
        var raw = original
        raw.c_lflag &= ~(UInt(ECHO | ICANON))
        raw.c_cc.6 = 1  // VMIN
        raw.c_cc.5 = 0  // VTIME
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        out(Ansi.altOn + Ansi.hideCursor)
    }
    func disable() {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        out(Ansi.showCursor + Ansi.altOff)
    }
}

enum Term { nonisolated(unsafe) static let raw = RawMode() }
let raw = Term.raw
func cleanupAndExit(_ code: Int32) -> Never {
    Term.raw.disable()
    exit(code)
}
signal(SIGINT) { _ in cleanupAndExit(0) }
signal(SIGTERM) { _ in cleanupAndExit(0) }

// MARK: - App state (single-threaded, main actor)

@MainActor
final class TUI {
    let cli = ContainerCLI()
    var containers: [ContainerInfo] = []
    var systemRunning = false
    var cursor = 0
    var message = ""
    var running = true

    func refresh() async {
        systemRunning = await cli.systemStatus()
        guard systemRunning else { containers = []; return }
        if let cs = try? await cli.listContainers(all: true) {
            containers = cs.sorted { $0.id < $1.id }
            cursor = min(cursor, max(0, containers.count - 1))
        }
    }

    var selected: ContainerInfo? {
        containers.indices.contains(cursor) ? containers[cursor] : nil
    }

    func render() {
        var s = Ansi.home
        let width = terminalWidth()
        // Title bar
        s += Ansi.rev + Ansi.bold
        s += pad(" container · \(systemRunning ? "engine running" : "engine stopped")  ", width)
        s += Ansi.reset + "\r\n"
        s += Ansi.clearLine() + "\r\n"

        // Header
        s += Ansi.bold + Ansi.dim
        s += row(["", "NAME", "STATE", "IMAGE", "CPU", "MEM", "IP"], width) + Ansi.reset + "\r\n"

        if !systemRunning {
            s += Ansi.clearLine() + "\r\n"
            s += "  " + Ansi.fg(214) + "Engine is stopped. Press 'e' to start it." + Ansi.reset + "\r\n"
        } else if containers.isEmpty {
            s += Ansi.clearLine() + "\r\n"
            s += "  " + Ansi.dim + "No containers. Use the GUI or `container run` to launch one." + Ansi.reset + "\r\n"
        } else {
            for (i, c) in containers.enumerated() {
                let sel = i == cursor
                let dot = c.runState.isRunning ? Ansi.fg(46) + "●" : Ansi.fg(214) + "○"
                let cols = [
                    "\(dot)\(Ansi.reset)",
                    c.id,
                    stateColored(c.runState),
                    c.shortImage,
                    "\(c.cpus)",
                    Format.bytes(c.memoryBytes),
                    c.ipv4?.split(separator: "/").first.map(String.init) ?? "-",
                ]
                if sel { s += Ansi.rev }
                s += Ansi.clearLine() + row(cols, width)
                if sel { s += Ansi.reset }
                s += "\r\n"
            }
        }

        // Footer
        s += Ansi.clearLine() + "\r\n"
        if !message.isEmpty {
            s += "  " + Ansi.fg(45) + message + Ansi.reset + "\r\n"
        }
        s += Ansi.dim
        s += "  ↑/↓ move   s start/stop   l logs   x remove   e engine   r refresh   q quit" + Ansi.reset
        s += "\(Ansi.esc)J" // clear to end of screen
        out(s)
    }

    // Column layout: fixed widths that sum roughly to terminal width.
    private func row(_ cols: [String], _ width: Int) -> String {
        let widths = [3, 16, 9, 26, 5, 9, 16]
        var line = " "
        for (i, c) in cols.enumerated() {
            let w = i < widths.count ? widths[i] : 10
            line += padVisible(c, w) + " "
        }
        return line
    }

    private func stateColored(_ st: RunState) -> String {
        let color = st.isRunning ? 46 : (st == .created ? 39 : 214)
        return Ansi.fg(color) + st.label + Ansi.reset
    }

    // Actions
    func toggleSelected() async {
        guard let c = selected else { return }
        do {
            if c.runState.isRunning { try await cli.stop(c.id); message = "Stopped \(c.id)" }
            else { try await cli.start(c.id); message = "Started \(c.id)" }
        } catch { message = "Error: \(error.localizedDescription)" }
        await refresh()
    }
    func removeSelected() async {
        guard let c = selected else { return }
        do { try await cli.remove(c.id, force: true); message = "Removed \(c.id)" }
        catch { message = "Error: \(error.localizedDescription)" }
        await refresh()
    }
    func toggleEngine() async {
        do {
            if systemRunning { try await cli.systemStop(); message = "Engine stopped" }
            else { message = "Starting engine…"; render(); try await cli.systemStart(); message = "Engine started" }
        } catch { message = "Error: \(error.localizedDescription)" }
        await refresh()
    }
    func followLogs() async {
        guard let c = selected, c.runState.isRunning else { message = "Select a running container"; return }
        raw.disable()
        out(Ansi.clear + "Logs for \(c.id) — press Ctrl-C to return\n\n")
        let (stream, cancel) = await cli.logStream(c.id, follow: true, tail: 100)
        let handler = LogInterrupt(cancel: cancel)
        handler.install()
        for await line in stream {
            out(line + "\n")
            if handler.stopped { break }
        }
        cancel()
        handler.restore()
        raw.enable()
        message = "Returned from logs"
    }
}

/// Lets Ctrl-C break out of the log follower without killing the app.
final class LogInterrupt: @unchecked Sendable {
    private let cancel: @Sendable () -> Void
    private(set) var stopped = false
    private var previous: (@convention(c) (Int32) -> Void)?
    init(cancel: @escaping @Sendable () -> Void) { self.cancel = cancel }
    func install() {
        LogInterruptBox.shared = self
        signal(SIGINT) { _ in LogInterruptBox.shared?.stopped = true }
    }
    func restore() {
        signal(SIGINT) { _ in cleanupAndExit(0) }
        LogInterruptBox.shared = nil
    }
}
enum LogInterruptBox { nonisolated(unsafe) static var shared: LogInterrupt? }

// MARK: - Layout utilities

func terminalWidth() -> Int {
    var w = winsize()
    if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &w) == 0, w.ws_col > 0 { return Int(w.ws_col) }
    return 100
}
func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? String(s.prefix(width)) : s + String(repeating: " ", count: width - s.count)
}
/// Pad accounting for ANSI escapes (which have zero visible width).
func padVisible(_ s: String, _ width: Int) -> String {
    let visible = stripAnsi(s).count
    if visible >= width { return s }
    return s + String(repeating: " ", count: width - visible)
}
func stripAnsi(_ s: String) -> String {
    var result = ""
    var inEsc = false
    for ch in s {
        if ch == "\u{1B}" { inEsc = true; continue }
        if inEsc { if ch == "m" { inEsc = false }; continue }
        result.append(ch)
    }
    return result
}

// MARK: - Input stream

/// Reads stdin bytes on a background thread and yields decoded keys.
enum Key: Sendable { case up, down, char(Character), quit }

func keyStream() -> AsyncStream<Key> {
    AsyncStream { continuation in
        Thread.detachNewThread {
            var buf = [UInt8](repeating: 0, count: 3)
            while true {
                let n = read(STDIN_FILENO, &buf, 3)
                if n <= 0 { continue }
                if n == 3 && buf[0] == 0x1B && buf[1] == 0x5B {
                    switch buf[2] {
                    case 0x41: continuation.yield(.up)
                    case 0x42: continuation.yield(.down)
                    default: break
                    }
                    continue
                }
                let c = Character(UnicodeScalar(buf[0]))
                continuation.yield(.char(c))
            }
        }
    }
}

// MARK: - Main loop

@MainActor
func mainLoop() async {
    let tui = TUI()
    raw.enable()
    out(Ansi.clear)
    await tui.refresh()
    tui.render()

    // Background auto-refresh every 2s.
    let ticker = Task { @MainActor in
        while tui.running {
            try? await Task.sleep(for: .seconds(2))
            await tui.refresh()
            tui.render()
        }
    }

    for await key in keyStream() {
        guard tui.running else { break }
        switch key {
        case .up: tui.cursor = max(0, tui.cursor - 1)
        case .down: tui.cursor = min(max(0, tui.containers.count - 1), tui.cursor + 1)
        case .char(let c):
            switch c {
            case "q": tui.running = false; ticker.cancel(); cleanupAndExit(0)
            case "j": tui.cursor = min(max(0, tui.containers.count - 1), tui.cursor + 1)
            case "k": tui.cursor = max(0, tui.cursor - 1)
            case "s": tui.message = ""; await tui.toggleSelected()
            case "x": tui.message = ""; await tui.removeSelected()
            case "e": tui.message = ""; await tui.toggleEngine()
            case "l": await tui.followLogs()
            case "r": tui.message = "Refreshed"; await tui.refresh()
            default: break
            }
        case .quit: tui.running = false; cleanupAndExit(0)
        }
        tui.render()
    }
}

await mainLoop()

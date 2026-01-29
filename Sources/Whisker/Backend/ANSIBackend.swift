#if os(macOS) || os(Linux)
import Foundation
#if os(Linux)
import Glibc
private func tcflag(_ v: Int32) -> UInt32 { UInt32(bitPattern: v) }
#else
import Darwin
private func tcflag(_ v: Int32) -> UInt { UInt(bitPattern: Int(v)) }
#endif

/// ANSI terminal backend - writes escape sequences to stdout
public final class ANSIBackend: TerminalBackend, @unchecked Sendable {
    private var originalTermios: termios?
    private var outputBuffer = Data()
    private var eventContinuation: AsyncStream<TerminalEvent>.Continuation?

    public var renderMode: RenderMode = .fullscreen

    public init() {}

    // MARK: - TerminalBackend

    public var size: Size {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0 {
            return Size(width: Int(ws.ws_col), height: Int(ws.ws_row))
        }
        return Size(width: 80, height: 24)  // Fallback
    }

    public func events() -> AsyncStream<TerminalEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation

            // Start input reading on background thread
            DispatchQueue.global(qos: .userInteractive).async {
                self.readInputLoop()
            }

            continuation.onTermination = { _ in
                self.eventContinuation = nil
            }
        }
    }

    public func write(_ commands: [RenderCommand]) {
        // Sort by position for optimal cursor movement
        let sorted = commands.sorted {
            ($0.position.y, $0.position.x) < ($1.position.y, $1.position.x)
        }

        var currentPos: Position?
        var currentStyle: Style?

        for cmd in sorted {
            // Move cursor if not already there
            if currentPos == nil || currentPos! != cmd.position {
                appendToBuffer(ANSI.moveTo(cmd.position))
            }

            // Update style if changed
            if currentStyle == nil || currentStyle! != cmd.cell.style {
                appendToBuffer(ANSI.style(cmd.cell.style))
                currentStyle = cmd.cell.style
            }

            // Write character
            appendToBuffer(String(cmd.cell.char))
            currentPos = Position(x: cmd.position.x + 1, y: cmd.position.y)
        }
    }

    public func flush() {
        guard !outputBuffer.isEmpty else { return }
        FileHandle.standardOutput.write(outputBuffer)
        outputBuffer.removeAll(keepingCapacity: true)
    }

    public func setup() throws {
        // Save current terminal settings
        var raw = termios()
        if tcgetattr(STDIN_FILENO, &raw) == 0 {
            originalTermios = raw

            // Enable raw mode
            raw.c_lflag &= ~tcflag(ECHO | ICANON | ISIG | IEXTEN)
            raw.c_iflag &= ~tcflag(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
            raw.c_oflag &= ~tcflag(OPOST)
            raw.c_cflag |= tcflag(CS8)
            raw.c_cc.16 = 0  // VMIN
            raw.c_cc.17 = 1  // VTIME (1/10 second timeout)

            tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        }

        switch renderMode {
        case .fullscreen:
            // Switch to alternate screen buffer
            appendToBuffer(ANSI.alternateScreenOn)
        case .inline:
            // Stay in normal scrollback buffer
            break
        }

        // Hide cursor
        appendToBuffer(ANSI.cursorHide)
        flush()
    }

    public func teardown() {
        // Show cursor
        appendToBuffer(ANSI.cursorShow)

        switch renderMode {
        case .fullscreen:
            // Switch back to main screen buffer
            appendToBuffer(ANSI.alternateScreenOff)
        case .inline:
            // Move cursor below the last rendered content so the shell prompt appears cleanly
            appendToBuffer("\r\n")
        }

        // Reset colors and attributes
        appendToBuffer(ANSI.reset)
        flush()

        // Restore original terminal settings
        if var original = originalTermios {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        }
    }

    public func moveCursor(to position: Position) {
        appendToBuffer(ANSI.moveTo(position))
    }

    public func setCursorVisible(_ visible: Bool) {
        appendToBuffer(visible ? ANSI.cursorShow : ANSI.cursorHide)
    }

    public func clearScreen() {
        appendToBuffer(ANSI.clearScreen)
        appendToBuffer(ANSI.moveTo(.zero))
    }

    public func clearLines(_ count: Int) {
        // Move up N lines (if needed), go to column 0, erase from cursor to end of screen
        if count > 0 {
            appendToBuffer("\u{1b}[\(count)A")
        }
        appendToBuffer("\r")
        appendToBuffer("\u{1b}[J")
    }

    public func writeRaw(_ string: String) {
        appendToBuffer(string)
    }

    // MARK: - Private

    private func appendToBuffer(_ string: String) {
        outputBuffer.append(contentsOf: string.utf8)
    }

    private func readInputLoop() {
        var buffer = [UInt8](repeating: 0, count: 16)

        while eventContinuation != nil {
            let bytesRead = read(STDIN_FILENO, &buffer, buffer.count)
            if bytesRead > 0 {
                if let event = parseInput(Array(buffer.prefix(bytesRead))) {
                    eventContinuation?.yield(event)
                }
            }
        }
    }

    private func parseInput(_ bytes: [UInt8]) -> TerminalEvent? {
        InputParser.parse(bytes)
    }
}

// MARK: - ANSI Escape Sequences

internal enum ANSI {
    static let escape = "\u{1b}"
    static let csi = "\u{1b}["

    static let reset = "\u{1b}[0m"
    static let clearScreen = "\u{1b}[2J"
    static let cursorHide = "\u{1b}[?25l"
    static let cursorShow = "\u{1b}[?25h"
    static let alternateScreenOn = "\u{1b}[?1049h"
    static let alternateScreenOff = "\u{1b}[?1049l"
    static let mouseTrackingOn = "\u{1b}[?1000h\u{1b}[?1006h"
    static let mouseTrackingOff = "\u{1b}[?1000l\u{1b}[?1006l"

    static func moveTo(_ pos: Position) -> String {
        "\u{1b}[\(pos.y + 1);\(pos.x + 1)H"
    }

    static func style(_ style: Style) -> String {
        var seq = "\u{1b}[0"  // Reset first

        // Attributes
        if style.attributes.contains(.bold) { seq += ";1" }
        if style.attributes.contains(.dim) { seq += ";2" }
        if style.attributes.contains(.italic) { seq += ";3" }
        if style.attributes.contains(.underline) { seq += ";4" }
        if style.attributes.contains(.blink) { seq += ";5" }
        if style.attributes.contains(.reverse) { seq += ";7" }
        if style.attributes.contains(.strikethrough) { seq += ";9" }

        seq += "m"

        // Foreground color
        seq += style.foreground.foregroundSequence

        // Background color
        if style.background != .default {
            seq += style.background.backgroundSequence
        }

        return seq
    }
}

#endif

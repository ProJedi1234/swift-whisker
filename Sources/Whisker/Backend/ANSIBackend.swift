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

    public var renderMode: RenderMode = .fullscreen

    public init() {}

    public var size: Size {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0 {
            return Size(width: Int(ws.ws_col), height: Int(ws.ws_row))
        }
        return Size(width: 80, height: 24)  // Fallback
    }

    public func write(_ commands: [RenderCommand]) {
        let sorted = commands.sorted {
            ($0.position.y, $0.position.x) < ($1.position.y, $1.position.x)
        }

        var currentPos: Position?
        var currentStyle: Style?

        for cmd in sorted {
            if currentPos == nil || currentPos! != cmd.position {
                appendToBuffer(ANSI.moveTo(cmd.position))
            }

            if currentStyle == nil || currentStyle! != cmd.cell.style {
                appendToBuffer(ANSI.style(cmd.cell.style))
                currentStyle = cmd.cell.style
            }

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
        var raw = termios()
        if tcgetattr(STDIN_FILENO, &raw) == 0 {
            originalTermios = raw

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
            appendToBuffer(ANSI.alternateScreenOn)
        case .inline:
            break
        }

        appendToBuffer(ANSI.cursorHide)
        flush()
    }

    public func teardown() {
        appendToBuffer(ANSI.cursorShow)

        switch renderMode {
        case .fullscreen:
            appendToBuffer(ANSI.alternateScreenOff)
        case .inline:
            appendToBuffer("\r\n")
        }

        appendToBuffer(ANSI.reset)
        flush()

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
        if count > 0 {
            appendToBuffer("\u{1b}[\(count)A")
        }
        appendToBuffer("\r")
        appendToBuffer("\u{1b}[J")
    }

    public func writeRaw(_ string: String) {
        appendToBuffer(string)
    }

    private func appendToBuffer(_ string: String) {
        outputBuffer.append(contentsOf: string.utf8)
    }
}

internal enum ANSI {
    static let reset = "\u{1b}[0m"
    static let clearScreen = "\u{1b}[2J"
    static let cursorHide = "\u{1b}[?25l"
    static let cursorShow = "\u{1b}[?25h"
    static let alternateScreenOn = "\u{1b}[?1049h"
    static let alternateScreenOff = "\u{1b}[?1049l"

    static func moveTo(_ pos: Position) -> String {
        "\u{1b}[\(pos.y + 1);\(pos.x + 1)H"
    }

    static func style(_ style: Style) -> String {
        var seq = "\u{1b}[0"  // Reset first

        if style.attributes.contains(.bold) { seq += ";1" }
        if style.attributes.contains(.dim) { seq += ";2" }
        if style.attributes.contains(.italic) { seq += ";3" }
        if style.attributes.contains(.underline) { seq += ";4" }
        if style.attributes.contains(.blink) { seq += ";5" }
        if style.attributes.contains(.reverse) { seq += ";7" }
        if style.attributes.contains(.strikethrough) { seq += ";9" }

        seq += "m"

        seq += style.foreground.foregroundSequence

        if style.background != .default {
            seq += style.background.backgroundSequence
        }

        return seq
    }
}

#endif

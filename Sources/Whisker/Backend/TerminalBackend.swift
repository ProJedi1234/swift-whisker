import Foundation

/// Input events from the terminal
public enum TerminalEvent: Sendable {
    case key(KeyEvent)
    case resize(Size)
    case mouse(MouseEvent)
}

/// A keyboard input event
public struct KeyEvent: Sendable {
    public let key: Key
    public let modifiers: KeyModifiers

    public init(key: Key, modifiers: KeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// Key types
public enum Key: Equatable, Sendable {
    case char(Character)
    case enter
    case tab
    case backspace
    case delete
    case escape
    case up, down, left, right
    case home, end
    case pageUp, pageDown
    case f(Int)  // F1-F12
}

/// Keyboard modifiers
public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let alt = KeyModifiers(rawValue: 1 << 2)
    public static let meta = KeyModifiers(rawValue: 1 << 3)
}

/// Mouse event
public struct MouseEvent: Sendable {
    public enum Kind: Sendable {
        case press(MouseButton)
        case release(MouseButton)
        case move
        case scroll(ScrollDirection)
    }

    public enum MouseButton: Sendable {
        case left, middle, right
    }

    public enum ScrollDirection: Sendable {
        case up, down
    }

    public let kind: Kind
    public let position: Position
    public let modifiers: KeyModifiers
}

/// Render command - a single cell to draw
public struct RenderCommand: Sendable {
    public let position: Position
    public let cell: Cell

    public init(position: Position, cell: Cell) {
        self.position = position
        self.cell = cell
    }
}

/// Protocol for terminal I/O backends
public protocol TerminalBackend: AnyObject, Sendable {
    /// Current render mode (fullscreen vs inline)
    var renderMode: RenderMode { get set }

    /// Current terminal size in cells
    var size: Size { get }

    /// Stream of input events
    func events() -> AsyncStream<TerminalEvent>

    /// Write render commands to the terminal
    func write(_ commands: [RenderCommand])

    /// Write a raw string directly to the output buffer
    func writeRaw(_ string: String)

    /// Flush the output buffer
    func flush()

    /// Set up the terminal (raw mode, alternate screen, etc.)
    func setup() throws

    /// Restore the terminal to its original state
    func teardown()

    /// Move cursor to position
    func moveCursor(to position: Position)

    /// Show or hide the cursor
    func setCursorVisible(_ visible: Bool)

    /// Clear the entire screen
    func clearScreen()

    /// Move up N lines and erase them (for inline re-rendering)
    func clearLines(_ count: Int)
}

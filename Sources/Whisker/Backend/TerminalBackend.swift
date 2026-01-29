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
    var renderMode: RenderMode { get set }
    var size: Size { get }

    func write(_ commands: [RenderCommand])
    func writeRaw(_ string: String)
    func flush()
    func setup() throws
    func teardown()
    func moveCursor(to position: Position)
    func setCursorVisible(_ visible: Bool)
    func clearScreen()
    func clearLines(_ count: Int)
}

import Foundation

/// A test backend that captures output for unit testing
public final class TestBackend: TerminalBackend, @unchecked Sendable {
    private var _size: Size
    private var cells: [[Cell]]
    public private(set) var cursorPosition: Position = .zero
    public private(set) var cursorVisible: Bool = true
    public var renderMode: RenderMode = .fullscreen

    public init(size: Size = Size(width: 80, height: 24)) {
        self._size = size
        self.cells = Array(
            repeating: Array(repeating: Cell.empty, count: size.width),
            count: size.height
        )
    }

    public var size: Size { _size }

    public func write(_ commands: [RenderCommand]) {
        for cmd in commands {
            if cmd.position.y >= 0 && cmd.position.y < _size.height &&
               cmd.position.x >= 0 && cmd.position.x < _size.width {
                cells[cmd.position.y][cmd.position.x] = cmd.cell
            }
        }
    }

    public func flush() {
        // No-op for test backend
    }

    public func setup() throws {
        // No-op for test backend
    }

    public func teardown() {
        // No-op for test backend
    }

    public func moveCursor(to position: Position) {
        cursorPosition = position
    }

    public func setCursorVisible(_ visible: Bool) {
        cursorVisible = visible
    }

    public func clearScreen() {
        cells = Array(
            repeating: Array(repeating: Cell.empty, count: _size.width),
            count: _size.height
        )
    }

    public func clearLines(_ count: Int) {
        // No-op for test backend
    }

    public func writeRaw(_ string: String) {
        // No-op for test backend
    }

    /// Get the cell at a position
    public func cell(at position: Position) -> Cell? {
        guard position.y >= 0 && position.y < _size.height &&
              position.x >= 0 && position.x < _size.width else {
            return nil
        }
        return cells[position.y][position.x]
    }

    /// Get the text content of a line (stripping trailing spaces)
    public func text(atLine line: Int) -> String {
        guard line >= 0 && line < _size.height else { return "" }
        return String(cells[line].map(\.char)).trimmingCharacters(in: .whitespaces)
    }

    /// Get all text content as a string (lines joined by newlines)
    public func allText() -> String {
        cells.map { row in
            String(row.map(\.char)).trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }

    /// Get a snapshot of the current screen for assertions
    public func snapshot() -> [[Cell]] {
        cells
    }

    public func resize(to newSize: Size) {
        _size = newSize
        cells = Array(
            repeating: Array(repeating: Cell.empty, count: newSize.width),
            count: newSize.height
        )
    }
}

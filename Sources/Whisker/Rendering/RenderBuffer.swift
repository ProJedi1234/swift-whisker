/// Buffer that collects render commands
public struct RenderBuffer {
    public var commands: [RenderCommand] = []

    public init() {}

    public mutating func draw(_ char: Character, at position: Position, style: Style = .default) {
        commands.append(RenderCommand(
            position: position,
            cell: Cell(char: char, style: style)
        ))
    }

    public mutating func draw(_ string: String, at position: Position, style: Style = .default) {
        var column = position.x
        for char in string {
            let width = terminalCellWidth(char)
            guard width > 0 else { continue }
            draw(char, at: Position(x: column, y: position.y), style: style)
            column += width
        }
    }

    mutating func drawClipped(
        _ string: String,
        at position: Position,
        maxWidth: Int,
        style: Style = .default,
        replacingControlCharacters: Bool = false
    ) {
        guard maxWidth > 0 else { return }
        var columnOffset = 0
        for character in string {
            let rendered = replacingControlCharacters
                ? terminalSafeCharacter(character)
                : character
            let width = terminalCellWidth(rendered)
            guard width > 0 else { continue }
            guard columnOffset + width <= maxWidth else { break }
            draw(
                rendered,
                at: Position(x: position.x + columnOffset, y: position.y),
                style: style
            )
            columnOffset += width
        }
    }

    public mutating func fill(_ rect: Rect, with char: Character = " ", style: Style = .default) {
        for y in rect.minY..<rect.maxY {
            for x in rect.minX..<rect.maxX {
                draw(char, at: Position(x: x, y: y), style: style)
            }
        }
    }
}

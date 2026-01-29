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
        for (i, char) in string.enumerated() {
            draw(char, at: Position(x: position.x + i, y: position.y), style: style)
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

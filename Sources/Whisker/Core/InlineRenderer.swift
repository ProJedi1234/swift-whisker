final class InlineRenderer {
    private(set) var lastRenderedLineCount: Int = 0
    private(set) var lastCursorContentRow: Int = 0
    private var isFirstRender: Bool = true

    func render(_ buffer: RenderBuffer, backend: TerminalBackend, focusedNode: Node?) {
        let contentHeight: Int
        if buffer.commands.isEmpty {
            contentHeight = 0
        } else {
            contentHeight = (buffer.commands.map { $0.position.y }.max() ?? 0) + 1
        }

        if !isFirstRender {
            backend.clearLines(lastCursorContentRow)
        }
        isFirstRender = false

        for row in 0..<contentHeight {
            let rowCommands = buffer.commands
                .filter { $0.position.y == row }
                .sorted { $0.position.x < $1.position.x }

            var line = ""
            var currentStyle: Style?

            var col = 0
            for cmd in rowCommands {
                if cmd.position.x > col {
                    if currentStyle != nil {
                        line += ANSI.reset
                        currentStyle = nil
                    }
                    line += String(repeating: " ", count: cmd.position.x - col)
                    col = cmd.position.x
                }

                if currentStyle == nil || currentStyle! != cmd.cell.style {
                    line += ANSI.style(cmd.cell.style)
                    currentStyle = cmd.cell.style
                }

                line += String(cmd.cell.char)
                col += 1
            }

            line += ANSI.reset
            line += "\u{1b}[K" // erase to end of line

            backend.writeRaw(line)
            if row < contentHeight - 1 {
                backend.writeRaw("\r\n")
            }
        }

        lastRenderedLineCount = contentHeight

        if let focused = focusedNode,
           focused[.getText] != nil {
            let cursorX = focused.frame.x + (focused[.cursorPosition] ?? 0)
            let cursorY = focused.frame.y
            let rowsUp = (contentHeight - 1) - cursorY
            if rowsUp > 0 {
                backend.writeRaw("\u{1b}[\(rowsUp)A")
            }
            backend.writeRaw("\r")
            if cursorX > 0 {
                backend.writeRaw("\u{1b}[\(cursorX)C")
            }
            backend.setCursorVisible(true)
            lastCursorContentRow = cursorY
        } else {
            backend.setCursorVisible(false)
            lastCursorContentRow = contentHeight - 1
        }

        backend.flush()
    }
}

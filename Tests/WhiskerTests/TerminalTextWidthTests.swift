import XCTest

@testable import Whisker

final class TerminalTextWidthTests: XCTestCase {
    func testCommonGraphemeWidths() {
        XCTAssertEqual(terminalTextWidth("ASCII"), 5)
        XCTAssertEqual(terminalTextWidth("e\u{301}"), 1)
        XCTAssertEqual(terminalTextWidth("東京"), 4)
        XCTAssertEqual(terminalTextWidth("🙂"), 2)
        XCTAssertEqual(terminalTextWidth("👨‍👩‍👧‍👦"), 2)
        XCTAssertEqual(terminalTextWidth("🇺🇸"), 2)
        XCTAssertEqual(terminalTextWidth("مرحبًا"), 5)
    }

    func testTextFieldRenderingAdvancesByTerminalColumns() {
        var text = "A東京🙂"
        let node = Node(viewType: TextField.self)
        let builder = NodeViewBuilder()
        builder.buildInputFieldNode(
            node,
            getText: { text },
            setText: { text = $0 },
            placeholder: "",
            isSecure: false
        )
        node.frame = Rect(x: 0, y: 0, width: 10, height: 1)
        var buffer = RenderBuffer()

        node.render?(node.frame, &buffer)

        XCTAssertEqual(buffer.commands.map(\.position.x), [0, 1, 3, 5])
        XCTAssertEqual(buffer.commands.map(\.cell.char), ["A", "東", "京", "🙂"])
    }

    func testFullscreenTextFieldCursorUsesTerminalColumns() {
        var text = "A東京🙂"
        let backend = TestBackend(size: Size(width: 20, height: 2))
        let app = Application(mode: .fullscreen, backend: backend) {
            TextField(get: { text }, set: { text = $0 })
        }
        defer { Application.shared = nil }

        app.rebuild()
        app.render()

        XCTAssertTrue(backend.cursorVisible)
        XCTAssertEqual(backend.cursorPosition.x, 7)
    }

    func testControlCharactersUseSafeSingleColumnPlaceholders() {
        XCTAssertEqual(
            terminalTextWidth("a\n\u{1b}b", replacingControlCharacters: true),
            4
        )
    }
}

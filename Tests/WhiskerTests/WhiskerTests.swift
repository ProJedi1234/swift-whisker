import XCTest

@testable import Whisker

final class WhiskerTests: XCTestCase {
    private func firstTextNode(in root: Node) -> Node? {
        var found: Node?
        root.traverse { node in
            if found == nil && node.viewType == Text.self {
                found = node
            }
        }
        return found
    }

    private func renderTree(_ node: Node, buffer: inout RenderBuffer) {
        if let render = node.render {
            render(node.frame, &buffer)
        }
        for child in node.children {
            renderTree(child, buffer: &buffer)
        }
    }

    // MARK: - Geometry Tests

    func testPositionArithmetic() {
        let a = Position(x: 10, y: 5)
        let b = Position(x: 3, y: 2)

        XCTAssertEqual(a + b, Position(x: 13, y: 7))
        XCTAssertEqual(a - b, Position(x: 7, y: 3))
    }

    func testSizeClamping() {
        let negative = Size(width: -5, height: -10)
        XCTAssertEqual(negative.width, 0)
        XCTAssertEqual(negative.height, 0)
    }

    func testRectContains() {
        let rect = Rect(x: 10, y: 10, width: 20, height: 10)

        XCTAssertTrue(rect.contains(Position(x: 15, y: 15)))
        XCTAssertTrue(rect.contains(Position(x: 10, y: 10)))  // Top-left corner
        XCTAssertFalse(rect.contains(Position(x: 30, y: 15)))  // Right edge (exclusive)
        XCTAssertFalse(rect.contains(Position(x: 5, y: 15)))  // Outside left
    }

    func testRectIntersection() {
        let a = Rect(x: 0, y: 0, width: 10, height: 10)
        let b = Rect(x: 5, y: 5, width: 10, height: 10)
        let c = Rect(x: 20, y: 20, width: 5, height: 5)

        let intersection = a.intersection(b)
        XCTAssertNotNil(intersection)
        XCTAssertEqual(intersection?.x, 5)
        XCTAssertEqual(intersection?.y, 5)
        XCTAssertEqual(intersection?.width, 5)
        XCTAssertEqual(intersection?.height, 5)

        XCTAssertNil(a.intersection(c))  // No overlap
    }

    // MARK: - Cell Tests

    func testCellEquality() {
        let a = Cell(char: "A", style: .default)
        let b = Cell(char: "A", style: .default)
        let c = Cell(char: "B", style: .default)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testStyleModifiers() {
        let style = Style.default
            .foreground(.red)
            .background(.blue)
            .bold()

        XCTAssertEqual(style.foreground, .red)
        XCTAssertEqual(style.background, .blue)
        XCTAssertTrue(style.attributes.contains(.bold))
    }

    // MARK: - Color Tests

    func testColorHex() {
        let color = Color.hex(0xFF5500)
        if case .rgb(let r, let g, let b) = color {
            XCTAssertEqual(r, 255)
            XCTAssertEqual(g, 85)
            XCTAssertEqual(b, 0)
        } else {
            XCTFail("Expected RGB color")
        }
    }

    // MARK: - TestBackend Tests

    func testTestBackendBasics() {
        let backend = TestBackend(size: Size(width: 10, height: 5))

        XCTAssertEqual(backend.size.width, 10)
        XCTAssertEqual(backend.size.height, 5)

        backend.write([
            RenderCommand(position: Position(x: 0, y: 0), cell: Cell(char: "H")),
            RenderCommand(position: Position(x: 1, y: 0), cell: Cell(char: "i"))
        ])

        XCTAssertEqual(backend.text(atLine: 0), "Hi")
    }

    // MARK: - View Tests

    func testTextCreation() {
        let text = Text("Hello")
        XCTAssertEqual(text.content, "Hello")
    }

    func testTextStringLiteral() {
        let text: Text = "Hello literal"
        XCTAssertEqual(text.content, "Hello literal")
    }

    func testTextStringInterpolation() {
        let text: Text = "Hello World \(123)"
        XCTAssertEqual(text.content, "Hello World 123")
    }

    func testTextVerbatim() {
        let text = Text(verbatim: "Raw \\(text)")
        XCTAssertEqual(text.content, "Raw \\(text)")
    }

    func testTextConcatenation() {
        let combined = Text("Hello") + Text(" World")
        XCTAssertEqual(combined.content, "Hello World")
    }

    func testVStackCreation() {
        let stack = VStack {
            Text("Line 1")
            Text("Line 2")
        }
        XCTAssertNotNil(stack)
    }

    func testForEachCreation() {
        let items = ["A", "B", "C"]
        let forEach = ForEach(items, id: \.self) { item in
            Text(item)
        }
        XCTAssertNotNil(forEach)
    }

    func testEnvironmentStylesCascadeToText() {
        let view = VStack {
            Text("A")
        }
        .foregroundColor(.red)
        .bold()

        let viewBuilder = NodeViewBuilder()
        let root = viewBuilder.buildNode(from: view)

        guard let textNode = firstTextNode(in: root) else {
            XCTFail("Expected to find a Text node")
            return
        }

        textNode.frame = Rect(x: 0, y: 0, width: 10, height: 1)
        var buffer = RenderBuffer()
        textNode.render?(textNode.frame, &buffer)

        guard let style = buffer.commands.first?.cell.style else {
            XCTFail("Expected rendered text style")
            return
        }

        XCTAssertEqual(style.foreground, .red)
        XCTAssertTrue(style.attributes.contains(.bold))
    }

    func testEnvironmentForegroundDoesNotOverrideExplicitTextColor() {
        let view = VStack {
            Text("A").foregroundColor(.green)
        }
        .foregroundColor(.red)

        let viewBuilder = NodeViewBuilder()
        let root = viewBuilder.buildNode(from: view)

        guard let textNode = firstTextNode(in: root) else {
            XCTFail("Expected to find a Text node")
            return
        }

        textNode.frame = Rect(x: 0, y: 0, width: 10, height: 1)
        var buffer = RenderBuffer()
        textNode.render?(textNode.frame, &buffer)

        guard let style = buffer.commands.first?.cell.style else {
            XCTFail("Expected rendered text style")
            return
        }

        XCTAssertEqual(style.foreground, .green)
    }

    func testHStackClampsChildWidthsToBounds() {
        let view = HStack(spacing: 1) {
            Text("ThisIsAVeryLongText")
            Text("Next")
        }

        let viewBuilder = NodeViewBuilder()
        let root = viewBuilder.buildNode(from: view)
        let bounds = Rect(x: 0, y: 0, width: 10, height: 1)

        root.frame = bounds
        root[.placeChildren]?(bounds)

        var buffer = RenderBuffer()
        renderTree(root, buffer: &buffer)

        let maxX = buffer.commands.map { $0.position.x }.max() ?? 0
        XCTAssertLessThan(maxX, bounds.width)
    }

}

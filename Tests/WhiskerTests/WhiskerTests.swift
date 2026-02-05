import XCTest

@testable import Whisker

final class WhiskerTests: XCTestCase {
    private struct CounterView: View {
        @State var count = 0
        var body: some View { Text("\(count)") }
    }

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
            RenderCommand(position: Position(x: 1, y: 0), cell: Cell(char: "i")),
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

    // MARK: - Integration Tests

    func testStateChangeSchedulesUpdate() {
        let backend = TestBackend(size: Size(width: 10, height: 5))
        let app = Application(mode: .inline, backend: backend) { EmptyView() }
        defer {
            Application.shared = nil
            NodeContext.current = nil
        }

        let node = Node(viewType: CounterView.self)
        NodeContext.current = node

        let view = CounterView()
        node.needsRebuild = false
        app.updateScheduled = false
        view.count = 1

        XCTAssertTrue(node.needsRebuild)
        XCTAssertTrue(app.updateScheduled)

        node.needsRebuild = false
        app.updateScheduled = false
        view.count = 1

        XCTAssertFalse(node.needsRebuild)
        XCTAssertFalse(app.updateScheduled)
    }

    func testFocusTraversalOrder() {
        let root = Node(viewType: EmptyView.self)
        let container = Node(viewType: EmptyView.self)
        let first = Node(viewType: EmptyView.self)
        let second = Node(viewType: EmptyView.self)
        first.isFocusable = true
        second.isFocusable = true

        container.addChild(first)
        root.addChild(container)
        root.addChild(second)

        XCTAssertTrue(root.findFirstFocusable() === first)
        XCTAssertTrue(first.findNextFocusable() === second)
        XCTAssertTrue(second.findPreviousFocusable() === first)
    }

    func testTextFieldKeyHandlingUpdatesTextAndCursor() {
        var text = ""
        let node = Node(viewType: TextField.self)
        let viewBuilder = NodeViewBuilder()
        viewBuilder.buildInputFieldNode(
            node,
            getText: { text },
            setText: { text = $0 },
            placeholder: "",
            isSecure: false
        )

        node[.keyHandler]?(KeyEvent(key: .char("A")))
        node[.keyHandler]?(KeyEvent(key: .char("B")))
        XCTAssertEqual(text, "AB")
        XCTAssertEqual(node[.cursorPosition], 2)

        node[.keyHandler]?(KeyEvent(key: .left))
        node[.keyHandler]?(KeyEvent(key: .char("C")))
        XCTAssertEqual(text, "ACB")
        XCTAssertEqual(node[.cursorPosition], 2)

        node[.keyHandler]?(KeyEvent(key: .home))
        node[.keyHandler]?(KeyEvent(key: .delete))
        XCTAssertEqual(text, "CB")

        node[.keyHandler]?(KeyEvent(key: .end))
        node[.keyHandler]?(KeyEvent(key: .backspace))
        XCTAssertEqual(text, "C")
    }

    func testSegmentedControlKeyHandlingClampsSelection() {
        var selection = 0
        let control = SegmentedControl(
            ["First", "Second", "Third"],
            selection: Binding(get: { selection }, set: { selection = $0 })
        )

        let viewBuilder = NodeViewBuilder()
        let node = viewBuilder.buildNode(from: control)

        node[.keyHandler]?(KeyEvent(key: .left))
        XCTAssertEqual(selection, 0)

        node[.keyHandler]?(KeyEvent(key: .right))
        XCTAssertEqual(selection, 1)

        node[.keyHandler]?(KeyEvent(key: .right))
        XCTAssertEqual(selection, 2)

        node[.keyHandler]?(KeyEvent(key: .right))
        XCTAssertEqual(selection, 2)
    }

    func testHStackSizeThatFitsRespectsWidthConstraint() {
        let layout = HStackLayout(spacing: 1)
        let view = HStack(spacing: 1) {
            Text("AAAAAAAAAA")
            Text("BBBBBBBBBB")
        }

        let viewBuilder = NodeViewBuilder()
        let root = viewBuilder.buildNode(from: view)
        let children = root.children.map { LayoutChild(node: $0) }

        let proposal = ProposedSize(width: .atMost(15), height: .exactly(1))
        let size = layout.sizeThatFits(proposal: proposal, children: children)

        XCTAssertLessThanOrEqual(size.width, 15)
    }

    func testSegmentedControlViewportShowsSelectedItem() {
        var selection = 5
        let options = [
            "Alpha", "Bravo", "Charlie", "Delta", "Echo",
            "Foxtrot", "Golf", "Hotel", "India", "Juliet",
        ]
        let control = SegmentedControl(
            options,
            selection: Binding(get: { selection }, set: { selection = $0 })
        )

        let viewBuilder = NodeViewBuilder()
        let node = viewBuilder.buildNode(from: control)

        let frameWidth = 30
        let proposal = ProposedSize(width: .atMost(frameWidth), height: .exactly(1))
        if let layoutFn = node.layout {
            let (size, _) = layoutFn(proposal, node.children)
            node.frame = Rect(x: 0, y: 0, width: size.width, height: size.height)
        }

        var buffer = RenderBuffer()
        node.render?(node.frame, &buffer)

        // The selected option "Foxtrot" should appear in the rendered output
        let rendered = buffer.commands.map { String($0.cell.char) }.joined()
        XCTAssertTrue(
            rendered.contains("Foxtrot"),
            "Selected item 'Foxtrot' should be visible in viewport, got: \(rendered)")
    }

    func testSegmentedControlWrapsSelectionWhenEnabled() {
        var selection = 0
        let control = SegmentedControl(
            ["First", "Second", "Third"],
            selection: Binding(get: { selection }, set: { selection = $0 }),
            wraps: true
        )

        let viewBuilder = NodeViewBuilder()
        let node = viewBuilder.buildNode(from: control)

        node[.keyHandler]?(KeyEvent(key: .left))
        XCTAssertEqual(selection, 2)

        node[.keyHandler]?(KeyEvent(key: .right))
        XCTAssertEqual(selection, 0)
    }

    func testSegmentedControlScrollShowsIndicators() {
        var selection = 0
        let options = [
            "Alpha", "Bravo", "Charlie", "Delta", "Echo",
            "Foxtrot", "Golf", "Hotel", "India", "Juliet",
        ]
        let control = SegmentedControl(
            options,
            selection: Binding(get: { selection }, set: { selection = $0 }),
            overflow: .scroll
        )

        let viewBuilder = NodeViewBuilder()
        let node = viewBuilder.buildNode(from: control)

        let frameWidth = 30
        let proposal = ProposedSize(width: .atMost(frameWidth), height: .exactly(1))
        if let layoutFn = node.layout {
            let (size, _) = layoutFn(proposal, node.children)
            node.frame = Rect(x: 0, y: 0, width: size.width, height: size.height)
        }

        var buffer = RenderBuffer()
        node.render?(node.frame, &buffer)

        let rendered = buffer.commands.map { String($0.cell.char) }.joined()
        // Right indicator should be present when scrolled to start
        XCTAssertTrue(
            rendered.contains("\u{203A}"),
            "Right scroll indicator should appear, got: \(rendered)")
    }

    func testSegmentedControlWrapLayoutMultipleLines() {
        var selection = 0
        let options = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
        let control = SegmentedControl(
            options,
            selection: Binding(get: { selection }, set: { selection = $0 }),
            overflow: .wrap
        )

        let viewBuilder = NodeViewBuilder()
        let node = viewBuilder.buildNode(from: control)

        // Total content: " Alpha  Bravo  Charlie  Delta  Echo  Foxtrot " = ~50 chars
        // With width 25 it should need multiple lines
        let frameWidth = 25
        let proposal = ProposedSize(width: .atMost(frameWidth), height: .unconstrained)
        if let layoutFn = node.layout {
            let (size, _) = layoutFn(proposal, node.children)
            XCTAssertGreaterThan(
                size.height, 1,
                "Wrap mode should use multiple lines for wide content")
            XCTAssertLessThanOrEqual(size.width, frameWidth)
        }
    }

    func testSegmentedControlWrapRendersAcrossLines() {
        var selection = 3
        let options = ["Alpha", "Bravo", "Charlie", "Delta", "Echo"]
        let control = SegmentedControl(
            options,
            selection: Binding(get: { selection }, set: { selection = $0 }),
            overflow: .wrap
        )

        let viewBuilder = NodeViewBuilder()
        let node = viewBuilder.buildNode(from: control)

        let frameWidth = 25
        let proposal = ProposedSize(width: .atMost(frameWidth), height: .unconstrained)
        if let layoutFn = node.layout {
            let (size, _) = layoutFn(proposal, node.children)
            node.frame = Rect(x: 0, y: 0, width: size.width, height: size.height)
        }

        var buffer = RenderBuffer()
        node.render?(node.frame, &buffer)

        // Verify content spans multiple y-coordinates
        let ys = Set(buffer.commands.map { $0.position.y })
        XCTAssertGreaterThan(ys.count, 1, "Wrap mode should render across multiple lines")

        // Selected item "Delta" should appear in the output
        let rendered = buffer.commands.map { String($0.cell.char) }.joined()
        XCTAssertTrue(
            rendered.contains("Delta"),
            "Selected item should be visible in wrapped output, got: \(rendered)")
    }
}

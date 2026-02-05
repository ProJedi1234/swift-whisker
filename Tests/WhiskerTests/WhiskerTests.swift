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

    // MARK: - Reconciliation Tests

    func testStateSurvivesRebuild() {
        struct CounterView2: View {
            @State var count = 0
            var body: some View { Text("\(count)") }
        }

        let viewBuilder = NodeViewBuilder()
        let node1 = viewBuilder.buildNode(from: CounterView2())
        node1.persistentState["count"] = 42

        let node2 = viewBuilder.buildNode(from: CounterView2(), existing: node1)
        XCTAssertEqual(node2.persistentState["count"] as? Int, 42)
    }

    func testStateSurvivesRebuildInNestedStack() {
        let viewBuilder = NodeViewBuilder()

        let view1 = VStack {
            Text("Header")
            Text("Content")
        }
        let node1 = viewBuilder.buildNode(from: view1)
        XCTAssertEqual(node1.children.count, 2)
        node1.children[1].persistentState["value"] = "Alice"

        let view2 = VStack {
            Text("Header")
            Text("Content")
        }
        let node2 = viewBuilder.buildNode(from: view2, existing: node1)
        XCTAssertEqual(node2.children.count, 2)
        XCTAssertEqual(node2.children[1].persistentState["value"] as? String, "Alice")
        XCTAssertNil(node2.children[0].persistentState["value"])
    }

    func testCursorPositionSurvivesRebuild() {
        var text = "Hello"
        let viewBuilder = NodeViewBuilder()

        let node1 = Node(viewType: TextField.self)
        NodeContext.current = node1
        viewBuilder.buildInputFieldNode(
            node1, getText: { text }, setText: { text = $0 },
            placeholder: "", isSecure: false
        )
        node1[.cursorPosition] = 2

        let node2 = Node(viewType: TextField.self)
        NodeContext.current = node2
        viewBuilder.buildInputFieldNode(
            node2, getText: { text }, setText: { text = $0 },
            placeholder: "", isSecure: false, existing: node1
        )
        XCTAssertEqual(node2[.cursorPosition], 2)
        NodeContext.current = nil
    }

    func testCursorPositionClampedWhenTextShrinks() {
        var text = "Hello"
        let viewBuilder = NodeViewBuilder()

        let node1 = Node(viewType: TextField.self)
        NodeContext.current = node1
        viewBuilder.buildInputFieldNode(
            node1, getText: { text }, setText: { text = $0 },
            placeholder: "", isSecure: false
        )
        node1[.cursorPosition] = 5

        text = "Hi"

        let node2 = Node(viewType: TextField.self)
        NodeContext.current = node2
        viewBuilder.buildInputFieldNode(
            node2, getText: { text }, setText: { text = $0 },
            placeholder: "", isSecure: false, existing: node1
        )
        XCTAssertEqual(node2[.cursorPosition], 2)
        NodeContext.current = nil
    }

    func testConditionalViewBranchChangeDiscardsState() {
        struct BranchA: View {
            @State var valueA = 0
            var body: some View { Text("\(valueA)") }
        }
        struct BranchB: View {
            @State var valueB = 0
            var body: some View { Text("\(valueB)") }
        }

        let viewBuilder = NodeViewBuilder()

        let condTrue: ConditionalView<BranchA, BranchB> = .trueView(BranchA())
        let node1 = viewBuilder.buildNode(from: condTrue)
        XCTAssertEqual(node1.conditionalBranch, true)
        node1.children.first?.persistentState["valueA"] = 99

        let condFalse: ConditionalView<BranchA, BranchB> = .falseView(BranchB())
        let node2 = viewBuilder.buildNode(from: condFalse, existing: node1)
        XCTAssertEqual(node2.conditionalBranch, false)
        XCTAssertNil(node2.children.first?.persistentState["valueA"] as? Int)
    }

    func testConditionalViewSameBranchPreservesState() {
        struct BranchA: View {
            @State var valueA = 0
            var body: some View { Text("\(valueA)") }
        }
        struct BranchB: View {
            @State var valueB = 0
            var body: some View { Text("\(valueB)") }
        }

        let viewBuilder = NodeViewBuilder()

        let cond1: ConditionalView<BranchA, BranchB> = .trueView(BranchA())
        let node1 = viewBuilder.buildNode(from: cond1)
        node1.children.first?.persistentState["valueA"] = 42

        let cond2: ConditionalView<BranchA, BranchB> = .trueView(BranchA())
        let node2 = viewBuilder.buildNode(from: cond2, existing: node1)
        XCTAssertEqual(node2.children.first?.persistentState["valueA"] as? Int, 42)
    }

    func testFrameworkStorageNotCarriedOver() {
        var text = "Hello"
        let viewBuilder = NodeViewBuilder()

        let node1 = Node(viewType: TextField.self)
        NodeContext.current = node1
        viewBuilder.buildInputFieldNode(
            node1, getText: { text }, setText: { text = $0 },
            placeholder: "old placeholder", isSecure: false
        )
        XCTAssertEqual(node1[.placeholder], "old placeholder")

        let node2 = Node(viewType: TextField.self)
        NodeContext.current = node2
        viewBuilder.buildInputFieldNode(
            node2, getText: { text }, setText: { text = $0 },
            placeholder: "new placeholder", isSecure: false, existing: node1
        )
        XCTAssertEqual(node2[.placeholder], "new placeholder")
        NodeContext.current = nil
    }

    func testViewTypeChangeClearsState() {
        let viewBuilder = NodeViewBuilder()

        let node1 = Node(viewType: Text.self)
        node1.persistentState["someKey"] = "oldValue"

        let button = Button("Click") {}
        let node2 = viewBuilder.buildNode(from: button, existing: node1)
        XCTAssertNil(node2.persistentState["someKey"])
    }

}

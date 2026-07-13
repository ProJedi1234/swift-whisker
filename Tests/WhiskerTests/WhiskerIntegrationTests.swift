import XCTest

@testable import Whisker

final class WhiskerIntegrationTests: XCTestCase {
    private struct CounterView: View {
        @State var count = 0
        var body: some View { Text("\(count)") }
    }

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

    func testStateBindingDoesNotRetainNode() {
        struct BindingHost {
            @State var value = ""
        }

        weak var weakNode: Node?
        var binding: Binding<String>?

        do {
            let node = Node(viewType: EmptyView.self)
            weakNode = node
            NodeContext.current = node

            let host = BindingHost()
            binding = host.$value

            NodeContext.current = nil
        }

        XCTAssertNil(weakNode)
        XCTAssertEqual(binding?.wrappedValue, "")
    }

    func testStateBindingCapturedDuringBuildWorksOutsideBuildPass() {
        struct BindingProbe: View {
            @Binding var value: Int
            let onBinding: (Binding<Int>) -> Void

            init(value: Binding<Int>, onBinding: @escaping (Binding<Int>) -> Void) {
                self._value = value
                self.onBinding = onBinding
                onBinding(value)
            }

            var body: some View { EmptyView() }
        }

        struct BindingHostView: View {
            @State var value = 0
            let onBinding: (Binding<Int>) -> Void

            var body: some View {
                BindingProbe(value: $value, onBinding: onBinding)
            }
        }

        let viewBuilder = NodeViewBuilder()
        var capturedBinding: Binding<Int>?

        let node = viewBuilder.buildNode(from: BindingHostView(onBinding: { capturedBinding = $0 }))
        XCTAssertNil(NodeContext.current)
        XCTAssertNotNil(capturedBinding)

        guard let binding = capturedBinding else {
            XCTFail("Expected binding to be captured during build")
            return
        }

        binding.wrappedValue = 7

        XCTAssertEqual(binding.wrappedValue, 7)
        XCTAssertTrue(node.persistentState.values.values.contains { ($0 as? Int) == 7 })
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

    func testTaskIdentityDistinguishesSameStringRepresentation() {
        XCTAssertNotEqual(TaskIdentity(1), TaskIdentity("1"))
        XCTAssertEqual(TaskIdentity(1), TaskIdentity(1))
        XCTAssertEqual(TaskIdentity("1"), TaskIdentity("1"))
    }

    func testTaskModifierSpawnsAndCompletes() {
        // Build a view tree that includes a .task modifier
        let viewBuilder = NodeViewBuilder()

        struct TaskTestView: View {
            @State var value = 0
            var body: some View {
                Text("hello")
                    .task {
                        // This should run on a background thread
                        value = 42
                    }
            }
        }

        let backend = TestBackend(size: Size(width: 40, height: 5))
        let app = Application(mode: .inline, backend: backend) { EmptyView() }
        defer {
            Application.shared = nil
            NodeContext.current = nil
        }

        let root = viewBuilder.buildNode(from: TaskTestView())

        // The task should have been spawned during buildNode
        // Find the TaskModifier node — it wraps the Text node
        var taskNode: Node?
        root.traverse { node in
            if node.activeTask != nil && taskNode == nil {
                taskNode = node
            }
        }
        XCTAssertNotNil(taskNode, "Expected a node with an active task")

        // Give the task time to complete (it has no sleep, should be near-instant)
        let expectation = self.expectation(description: "Task completes")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)

        // The @State mutation should have been written to persistentState
        // Check if scheduleUpdate was called
        XCTAssertTrue(app.updateScheduled, "Expected scheduleUpdate to be called by task's @State mutation")
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

    func testTextFieldInsertsTextAndPasteAtomicallyAtCursor() {
        var text = "start-end"
        let node = Node(viewType: TextField.self)
        let viewBuilder = NodeViewBuilder()
        viewBuilder.buildInputFieldNode(
            node,
            getText: { text },
            setText: { text = $0 },
            placeholder: "",
            isSecure: false
        )
        node[.cursorPosition] = 6

        node[.textInputHandler]?("long🙂\n\u{1b}[A")

        XCTAssertEqual(text, "start-long🙂\n\u{1b}[Aend")
        XCTAssertEqual(node[.cursorPosition], "start-long🙂\n\u{1b}[A".count)
    }

    func testTextFieldRendersPastedControlCharactersSafely() {
        var text = "a\u{1b}\nb"
        let node = Node(viewType: TextField.self)
        let viewBuilder = NodeViewBuilder()
        viewBuilder.buildInputFieldNode(
            node,
            getText: { text },
            setText: { text = $0 },
            placeholder: "",
            isSecure: false
        )
        node.frame = Rect(x: 0, y: 0, width: 4, height: 1)
        var buffer = RenderBuffer()

        node.render?(node.frame, &buffer)

        XCTAssertEqual(buffer.commands.map(\.cell.char), ["a", " ", " ", "b"])
    }
}

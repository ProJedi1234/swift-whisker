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
}

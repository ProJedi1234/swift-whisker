import XCTest

@testable import Whisker

final class WhiskerReconciliationTests: XCTestCase {
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

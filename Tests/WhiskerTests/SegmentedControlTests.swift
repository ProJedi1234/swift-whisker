import XCTest

@testable import Whisker

final class SegmentedControlTests: XCTestCase {

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

    func testSegmentedControlViewportShowsSelectedItem() {
        var selection = 5
        let options = [
            "Alpha", "Bravo", "Charlie", "Delta", "Echo",
            "Foxtrot", "Golf", "Hotel", "India", "Juliet"
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
            "Foxtrot", "Golf", "Hotel", "India", "Juliet"
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
}

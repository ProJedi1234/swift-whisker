import XCTest

@testable import Whisker

final class SelectListTests: XCTestCase {

    private func makeApp(
        backend: TestBackend = TestBackend(size: Size(width: 40, height: 12)),
        @ViewBuilder rootView: @escaping () -> some View
    ) -> Application {
        Application(mode: .fullscreen, backend: backend, rootView: rootView)
    }

    override func tearDown() {
        Application.shared = nil
        NodeContext.current = nil
        super.tearDown()
    }

    // MARK: - Selection movement

    func testUpDownMoveSelectionWhenFocused() {
        var selection = 0
        let app = makeApp {
            VStack {
                SelectList(
                    ["Alpha", "Bravo", "Charlie"],
                    selection: Binding(get: { selection }, set: { selection = $0 })
                )
                Button("ok") {}
            }
        }

        app.rebuild()
        XCTAssertEqual(app.focusedIndex, 0, "SelectList should join the focus ring first")

        XCTAssertTrue(app.handleKey(KeyEvent(key: .down)))
        XCTAssertEqual(selection, 1)
        XCTAssertEqual(app.focusedIndex, 0, "Consumed .down must not move focus")

        XCTAssertTrue(app.handleKey(KeyEvent(key: .down)))
        XCTAssertEqual(selection, 2)

        XCTAssertTrue(app.handleKey(KeyEvent(key: .up)))
        XCTAssertTrue(app.handleKey(KeyEvent(key: .up)))
        XCTAssertEqual(selection, 0)
        XCTAssertEqual(app.focusedIndex, 0)
    }

    func testBoundaryKeysClampAndStayConsumed() {
        var selection = 0
        let app = makeApp {
            VStack {
                SelectList(
                    ["Alpha", "Bravo"],
                    selection: Binding(get: { selection }, set: { selection = $0 })
                )
                Button("ok") {}
            }
        }

        app.rebuild()
        XCTAssertEqual(app.focusedIndex, 0)

        // .up at the top edge: clamped, consumed, focus untouched
        XCTAssertTrue(app.handleKey(KeyEvent(key: .up)))
        XCTAssertEqual(selection, 0)
        XCTAssertEqual(app.focusedIndex, 0, ".up at boundary must not fall back to focus traversal")

        // .down at the bottom edge: clamped, consumed, focus untouched
        XCTAssertTrue(app.handleKey(KeyEvent(key: .down)))
        XCTAssertEqual(selection, 1)
        XCTAssertTrue(app.handleKey(KeyEvent(key: .down)))
        XCTAssertEqual(selection, 1)
        XCTAssertEqual(app.focusedIndex, 0, ".down at boundary must not fall back to focus traversal")
    }

    // MARK: - Highlight rendering

    func testSelectedRowRendersPointerAndInverseBold() {
        let backend = TestBackend(size: Size(width: 30, height: 8))
        var selection = 1
        let app = makeApp(backend: backend) {
            SelectList(
                ["Alpha", "Bravo", "Charlie"],
                selection: Binding(get: { selection }, set: { selection = $0 })
            )
        }

        app.rebuild()
        app.render()

        XCTAssertEqual(backend.text(atLine: 0), "Alpha")
        XCTAssertEqual(backend.text(atLine: 1), "\u{276F} Bravo")
        XCTAssertEqual(backend.text(atLine: 2), "Charlie")

        // Selected row carries reverse + bold across the pointer and label
        let pointerCell = backend.cell(at: Position(x: 0, y: 1))
        XCTAssertTrue(pointerCell?.style.attributes.contains(.reverse) ?? false)
        XCTAssertTrue(pointerCell?.style.attributes.contains(.bold) ?? false)
        let labelCell = backend.cell(at: Position(x: 2, y: 1))
        XCTAssertEqual(labelCell?.char, "B")
        XCTAssertTrue(labelCell?.style.attributes.contains(.reverse) ?? false)

        // Unselected rows carry neither
        let unselectedCell = backend.cell(at: Position(x: 2, y: 0))
        XCTAssertEqual(unselectedCell?.char, "A")
        XCTAssertFalse(unselectedCell?.style.attributes.contains(.reverse) ?? true)
    }

    // MARK: - Sliding window

    func testWindowSlidesAndShowsOverflowIndicators() {
        let backend = TestBackend(size: Size(width: 30, height: 8))
        let options = [
            "Alpha", "Bravo", "Charlie", "Delta", "Echo",
            "Foxtrot", "Golf", "Hotel", "India", "Juliet"
        ]
        var selection = 0
        let app = makeApp(backend: backend) {
            SelectList(
                options,
                selection: Binding(get: { selection }, set: { selection = $0 }),
                visibleRows: 5
            )
        }

        // At the top: no up indicator, down indicator visible, window = rows 0..2
        app.rebuild()
        app.render()
        XCTAssertEqual(backend.text(atLine: 0), "", "No up indicator when scrolled to the top")
        XCTAssertEqual(backend.text(atLine: 1), "\u{276F} Alpha")
        XCTAssertEqual(backend.text(atLine: 2), "Bravo")
        XCTAssertEqual(backend.text(atLine: 3), "Charlie")
        XCTAssertEqual(backend.text(atLine: 4), "▼", "Down indicator when more options below")
        XCTAssertEqual(backend.text(atLine: 5), "", "List must not exceed visibleRows")

        // Mid-list: both indicators, selection kept visible
        selection = 5
        app.rebuild()
        app.render()
        XCTAssertEqual(backend.text(atLine: 0), "▲")
        XCTAssertTrue(backend.allText().contains("Foxtrot"), "Selection must stay in the window")
        XCTAssertEqual(backend.text(atLine: 4), "▼")
        XCTAssertFalse(backend.allText().contains("Alpha"), "Rows above the window are hidden")

        // At the bottom: up indicator only
        selection = 9
        app.rebuild()
        app.render()
        XCTAssertEqual(backend.text(atLine: 0), "▲")
        XCTAssertEqual(backend.text(atLine: 3), "\u{276F} Juliet")
        XCTAssertEqual(backend.text(atLine: 4), "", "No down indicator at the bottom")
    }

    func testShortListShowsNoIndicators() {
        let backend = TestBackend(size: Size(width: 30, height: 8))
        var selection = 0
        let app = makeApp(backend: backend) {
            SelectList(
                ["Alpha", "Bravo"],
                selection: Binding(get: { selection }, set: { selection = $0 }),
                visibleRows: 5
            )
        }

        app.rebuild()
        app.render()
        XCTAssertEqual(backend.text(atLine: 0), "\u{276F} Alpha")
        XCTAssertEqual(backend.text(atLine: 1), "Bravo")
        XCTAssertFalse(backend.allText().contains("▲"))
        XCTAssertFalse(backend.allText().contains("▼"))
    }

    // MARK: - Shrinking options

    func testSelectionClampsWhenOptionsShrink() {
        let backend = TestBackend(size: Size(width: 30, height: 8))
        var options = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
        var selection = 5
        let app = makeApp(backend: backend) {
            SelectList(
                options,
                selection: Binding(get: { selection }, set: { selection = $0 })
            )
        }

        app.rebuild()
        app.render()
        XCTAssertEqual(backend.text(atLine: 5), "\u{276F} Foxtrot")

        // A filter above the list narrows the options; the stale index must
        // clamp to the last row rather than crash.
        options = ["Alpha", "Bravo", "Charlie"]
        app.rebuild()
        app.render()
        XCTAssertEqual(backend.text(atLine: 2), "\u{276F} Charlie", "Out-of-range selection renders clamped to the last row")
        XCTAssertEqual(backend.text(atLine: 3), "", "Dropped rows must not linger")

        // Key handling starts from the clamped position
        XCTAssertTrue(app.handleKey(KeyEvent(key: .up)))
        XCTAssertEqual(selection, 1)
    }

    // MARK: - Empty options

    func testEmptyOptionsRenderBenignlyAndConsumeNothing() {
        let backend = TestBackend(size: Size(width: 30, height: 8))
        var selection = 0
        let app = makeApp(backend: backend) {
            VStack {
                SelectList(
                    [],
                    selection: Binding(get: { selection }, set: { selection = $0 })
                )
                Button("ok") {}
            }
        }

        app.rebuild()
        app.render()

        let ring = FocusManager.allFocusableNodes(root: app.rootNode)
        XCTAssertEqual(ring.count, 1, "An empty SelectList must not join the focus ring")
        XCTAssertTrue(app.focusedNode === ring[0])

        // Up/down traverse focus normally; the empty list never consumes them
        XCTAssertTrue(app.handleKey(KeyEvent(key: .down)))
        XCTAssertTrue(app.focusedNode === ring[0], "Single-item ring wraps to itself")
        XCTAssertEqual(selection, 0)
    }
}

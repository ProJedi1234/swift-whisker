import XCTest

@testable import Whisker

final class SelectListTests: XCTestCase {

    private func makeApp(
        backend: TestBackend = TestBackend(size: Size(width: 30, height: 20)),
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

    func testArrowsMoveSelection() {
        var choice = 0
        let app = makeApp {
            SelectList(
                ["alpha", "beta", "gamma"],
                selection: Binding(get: { choice }, set: { choice = $0 }))
        }
        app.rebuild()

        XCTAssertTrue(app.handleKey(KeyEvent(key: .down)))
        XCTAssertEqual(choice, 1)
        XCTAssertTrue(app.handleKey(KeyEvent(key: .down)))
        XCTAssertEqual(choice, 2)
        XCTAssertTrue(app.handleKey(KeyEvent(key: .up)))
        XCTAssertEqual(choice, 1)
    }

    // MARK: - Boundaries hand focus onward

    func testDownAtBottomReleasesFocusInsteadOfTrapping() {
        var choice = 1
        var text = ""
        let app = makeApp {
            VStack {
                SelectList(
                    ["alpha", "beta"],
                    selection: Binding(get: { choice }, set: { choice = $0 }))
                TextField("after", get: { text }, set: { text = $0 })
            }
        }
        app.rebuild()
        XCTAssertEqual(app.focusedIndex, 0, "The list starts focused")

        // Selection is already on the last row, so .down has nowhere to go
        // inside the list and must fall through to focus traversal.
        XCTAssertTrue(app.handleKey(KeyEvent(key: .down)))
        XCTAssertEqual(choice, 1, "Selection stays put at the boundary")
        XCTAssertEqual(app.focusedIndex, 1, "Focus moves on to the next control")
    }

    func testUpAtTopReleasesFocusInsteadOfTrapping() {
        var choice = 0
        var text = ""
        let app = makeApp {
            VStack {
                TextField("before", get: { text }, set: { text = $0 })
                SelectList(
                    ["alpha", "beta"],
                    selection: Binding(get: { choice }, set: { choice = $0 }))
            }
        }
        app.rebuild()
        XCTAssertTrue(app.handleKey(KeyEvent(key: .tab)))
        XCTAssertEqual(app.focusedIndex, 1, "Focus starts on the list")

        XCTAssertTrue(app.handleKey(KeyEvent(key: .up)))
        XCTAssertEqual(choice, 0, "Selection stays put at the boundary")
        XCTAssertEqual(app.focusedIndex, 0, "Focus moves back to the field above")
    }

    func testWrapsCyclesAndKeepsFocus() {
        var choice = 2
        var text = ""
        let app = makeApp {
            VStack {
                SelectList(
                    ["alpha", "beta", "gamma"],
                    selection: Binding(get: { choice }, set: { choice = $0 }),
                    wraps: true)
                TextField("after", get: { text }, set: { text = $0 })
            }
        }
        app.rebuild()

        XCTAssertTrue(app.handleKey(KeyEvent(key: .down)))
        XCTAssertEqual(choice, 0, "Wrapping list cycles to the top")
        XCTAssertEqual(app.focusedIndex, 0, "A wrapping list keeps focus at the boundary")

        XCTAssertTrue(app.handleKey(KeyEvent(key: .up)))
        XCTAssertEqual(choice, 2, "Wrapping list cycles to the bottom")
        XCTAssertEqual(app.focusedIndex, 0)
    }

    // MARK: - Submit and cancel

    func testEnterSubmitsSelectedIndex() {
        var choice = 0
        var submitted: Int?
        let app = makeApp {
            SelectList(
                ["alpha", "beta", "gamma"],
                selection: Binding(get: { choice }, set: { choice = $0 }),
                onSubmit: { submitted = $0 })
        }
        app.rebuild()

        _ = app.handleKey(KeyEvent(key: .down))
        XCTAssertTrue(app.handleKey(KeyEvent(key: .enter)))
        XCTAssertEqual(submitted, 1, "Enter reports the selected index")
    }

    func testEscapeCancels() {
        var choice = 0
        var cancelled = false
        let app = makeApp {
            SelectList(
                ["alpha", "beta"],
                selection: Binding(get: { choice }, set: { choice = $0 }),
                onCancel: { cancelled = true })
        }
        app.rebuild()

        XCTAssertTrue(app.handleKey(KeyEvent(key: .escape)))
        XCTAssertTrue(cancelled)
    }

    func testEnterWithoutHandlerIsLeftToTheSurroundingView() {
        var choice = 0
        var pressed = false
        let app = makeApp {
            VStack {
                SelectList(
                    ["alpha", "beta"],
                    selection: Binding(get: { choice }, set: { choice = $0 }))
                Button("ok") { pressed = true }
            }
            .onKeyPress { event in
                if event.key == .enter {
                    pressed = true
                    return .handled
                }
                return .ignored
            }
        }
        app.rebuild()

        XCTAssertTrue(app.handleKey(KeyEvent(key: .enter)))
        XCTAssertTrue(pressed, "An unhandled .enter should bubble to the ancestor handler")
    }

    // MARK: - Degenerate inputs

    func testEmptyOptionsStayOutOfTheFocusRing() {
        var choice = 0
        let app = makeApp {
            VStack {
                SelectList([], selection: Binding(get: { choice }, set: { choice = $0 }))
                Button("ok") {}
            }
        }
        app.rebuild()

        let ring = FocusManager.allFocusableNodes(root: app.rootNode)
        XCTAssertEqual(ring.count, 1, "An empty list is not a focus stop")
    }

    func testSelectionBeyondOptionsIsClamped() {
        var choice = 99
        let app = makeApp {
            SelectList(
                ["alpha", "beta"], selection: Binding(get: { choice }, set: { choice = $0 }))
        }
        app.rebuild()

        // Clamped to the last row, so .up lands on the row above it.
        XCTAssertTrue(app.handleKey(KeyEvent(key: .up)))
        XCTAssertEqual(choice, 0)
    }

    // MARK: - Windowing

    func testWindowNeverExceedsVisibleRows() {
        let options = (1...20).map { "option-\($0)" }
        for visibleRows in 1...6 {
            let list = SelectList(options, selection: .constant(10), visibleRows: visibleRows)
            XCTAssertLessThanOrEqual(
                list.window().height, visibleRows,
                "A list with visibleRows=\(visibleRows) must not draw more rows than that")
        }
    }

    func testWindowKeepsSelectionVisibleAndReportsOverflow() {
        let options = (1...20).map { "option-\($0)" }

        let atTop = SelectList(options, selection: .constant(0), visibleRows: 6).window()
        XCTAssertTrue(atTop.range.contains(0))
        XCTAssertFalse(atTop.hasMoreAbove, "Nothing above the first row")
        XCTAssertTrue(atTop.hasMoreBelow)

        let inMiddle = SelectList(options, selection: .constant(10), visibleRows: 6).window()
        XCTAssertTrue(inMiddle.range.contains(10))
        XCTAssertTrue(inMiddle.hasMoreAbove)
        XCTAssertTrue(inMiddle.hasMoreBelow)

        let atBottom = SelectList(options, selection: .constant(19), visibleRows: 6).window()
        XCTAssertTrue(atBottom.range.contains(19))
        XCTAssertTrue(atBottom.hasMoreAbove)
        XCTAssertFalse(atBottom.hasMoreBelow, "Nothing below the last row")
    }

    func testShortListShowsEveryOptionWithoutMarkers() {
        let window = SelectList(["a", "b"], selection: .constant(0), visibleRows: 10).window()
        XCTAssertEqual(window.range, 0..<2)
        XCTAssertFalse(window.showsMarkers)
        XCTAssertEqual(window.height, 2)
    }

    // MARK: - Rendering

    func testFocusedListMarksSelectionWithPointerAndBold() {
        let backend = TestBackend(size: Size(width: 30, height: 10))
        var choice = 1
        let app = makeApp(backend: backend) {
            SelectList(
                ["alpha", "beta"], selection: Binding(get: { choice }, set: { choice = $0 }))
        }
        app.rebuild()
        app.render()

        XCTAssertTrue(backend.text(atLine: 1).contains("\u{276F} beta"), "Selected row is pointed at")
        let cell = backend.cell(at: Position(x: 0, y: 1))
        XCTAssertTrue(cell?.style.attributes.contains(.reverse) ?? false)
        XCTAssertTrue(
            cell?.style.attributes.contains(.bold) ?? false, "Focused selection is bold")
    }

    func testUnfocusedListDropsThePointerAndBold() {
        let backend = TestBackend(size: Size(width: 30, height: 10))
        var choice = 1
        var text = ""
        let app = makeApp(backend: backend) {
            // Leading alignment so the rows start at x = 0 and the styled
            // cells are at known positions.
            VStack(alignment: .leading) {
                TextField("filter", get: { text }, set: { text = $0 })
                SelectList(
                    ["alpha", "beta"], selection: Binding(get: { choice }, set: { choice = $0 }))
            }
        }
        app.rebuild()
        app.render()
        XCTAssertEqual(app.focusedIndex, 0, "Focus is on the field, not the list")

        let selectedLine = backend.text(atLine: 2)
        XCTAssertTrue(selectedLine.contains("beta"))
        XCTAssertFalse(
            selectedLine.contains("\u{276F}"),
            "An unfocused list must not imply the arrows are going to it")

        let cell = backend.cell(at: Position(x: 0, y: 2))
        XCTAssertTrue(
            cell?.style.attributes.contains(.reverse) ?? false,
            "The selection is still visible when unfocused")
        XCTAssertFalse(
            cell?.style.attributes.contains(.bold) ?? false,
            "Bold is reserved for the focused list")
    }

    // MARK: - The whole picker flow

    func testFilterThenTabThenSubmitPicksTheFilteredOption() {
        let all = ["cbx", "whisker", "stele", "whiskey"]
        var filter = ""
        var index = 0
        var picked: String?

        let app = makeApp {
            VStack(alignment: .leading) {
                TextField("filter", get: { filter }, set: { filter = $0 })
                SelectList(
                    all.filter { filter.isEmpty || $0.contains(filter) },
                    selection: Binding(get: { index }, set: { index = $0 }),
                    onSubmit: { picked = all.filter { filter.isEmpty || $0.contains(filter) }[$0] },
                    onCancel: { picked = nil })
            }
        }
        app.rebuild()

        // Type into the filter: "whisk" leaves whisker and whiskey.
        for character in "whisk" {
            XCTAssertTrue(app.handleKey(KeyEvent(key: .char(character))))
        }
        XCTAssertEqual(filter, "whisk")

        // Tab to the list, move down to the second match, submit.
        XCTAssertTrue(app.handleKey(KeyEvent(key: .tab)))
        app.rebuild()
        XCTAssertTrue(app.handleKey(KeyEvent(key: .down)))
        XCTAssertTrue(app.handleKey(KeyEvent(key: .enter)))

        XCTAssertEqual(picked, "whiskey", "Enter should report the filtered option under the cursor")
    }

    func testSelectionStaysValidWhenTheFilterShrinksTheOptions() {
        var options = ["alpha", "beta", "gamma"]
        var choice = 0
        let app = makeApp {
            SelectList(options, selection: Binding(get: { choice }, set: { choice = $0 }))
        }
        app.rebuild()

        _ = app.handleKey(KeyEvent(key: .down))
        _ = app.handleKey(KeyEvent(key: .down))
        XCTAssertEqual(choice, 2)

        // The filter narrows the list out from under the selection.
        options = ["alpha"]
        app.rebuild()
        app.render()

        // Clamped, so .enter reports a valid index rather than trapping.
        var submitted: Int?
        let submitApp = makeApp {
            SelectList(
                options,
                selection: Binding(get: { choice }, set: { choice = $0 }),
                onSubmit: { submitted = $0 })
        }
        submitApp.rebuild()
        XCTAssertTrue(submitApp.handleKey(KeyEvent(key: .enter)))
        XCTAssertEqual(submitted, 0, "A stale index is clamped into range")
    }

    func testWideOptionsAreMeasuredInTerminalCells() {
        // "猫猫" is two characters but four terminal cells, so a width taken
        // from String.count would clip the row.
        let selectList = SelectList(["ab", "\u{732B}\u{732B}"], selection: .constant(0))
        let node = NodeViewBuilder().buildNode(from: selectList)

        let (size, _) = node.layout!(
            ProposedSize(width: .unconstrained, height: .unconstrained), node.children)

        // Four cells for the widest option plus the two-column pointer gutter.
        XCTAssertEqual(size.width, 6)
    }

    func testOverflowMarkersAreDrawn() {
        let backend = TestBackend(size: Size(width: 30, height: 10))
        let options = (1...20).map { "option-\($0)" }
        var choice = 10
        let app = makeApp(backend: backend) {
            SelectList(
                options,
                selection: Binding(get: { choice }, set: { choice = $0 }),
                visibleRows: 5)
        }
        app.rebuild()
        app.render()

        XCTAssertTrue(backend.text(atLine: 0).contains("\u{25B2}"), "More above is marked")
        XCTAssertTrue(backend.text(atLine: 4).contains("\u{25BC}"), "More below is marked")
    }
}

import XCTest

@testable import Whisker

/// Who is in the focus ring, and how focus moves between them.
final class FocusRingTests: KeyEventTestCase {

    // MARK: - Tab traversal across a mixed focus ring

    func testTabTraversalAcrossTextFieldAndFocusableComposite() {
        var text = ""
        let app = makeApp {
            VStack {
                TextField("name", get: { text }, set: { text = $0 })
                ProbeView().focusable()
                Button("ok") {}
            }
        }

        app.rebuild()
        let ring = FocusManager.allFocusableNodes(root: app.rootNode)
        XCTAssertEqual(ring.count, 3, "TextField, focusable composite, and Button should all be in the ring")

        XCTAssertTrue(app.focusedNode === ring[0])

        XCTAssertTrue(app.handleKey(KeyEvent(key: .tab)))
        XCTAssertTrue(app.focusedNode === ring[1], "Tab should reach the focusable composite")

        XCTAssertTrue(app.handleKey(KeyEvent(key: .tab)))
        XCTAssertTrue(app.focusedNode === ring[2])

        XCTAssertTrue(app.handleKey(KeyEvent(key: .tab)))
        XCTAssertTrue(app.focusedNode === ring[0], "Tab should wrap around the ring")

        XCTAssertTrue(app.handleKey(KeyEvent(key: .tab, modifiers: .shift)))
        XCTAssertTrue(app.focusedNode === ring[2], "Shift-tab should traverse backwards")
    }

    // MARK: - Ring membership

    func testFocusableFalseStaysOutOfFocusRing() {
        let app = makeApp {
            VStack {
                ProbeView().focusable(false)
                Button("ok") {}
            }
        }

        app.rebuild()
        let ring = FocusManager.allFocusableNodes(root: app.rootNode)
        XCTAssertEqual(ring.count, 1, "focusable(false) should not join the focus ring")
    }

    func testFocusableOnControlAddsNoDuplicateStop() {
        let app = makeApp {
            VStack {
                Button("ok") {}.focusable()
                Button("cancel") {}
            }
        }

        app.rebuild()
        let ring = FocusManager.allFocusableNodes(root: app.rootNode)
        XCTAssertEqual(ring.count, 2, ".focusable() on an already-focusable control must not add a second stop")
    }

    func testFocusableFalseRemovesControlFromRing() {
        var text = ""
        let app = makeApp {
            VStack {
                TextField("name", get: { text }, set: { text = $0 }).focusable(false)
                Button("ok") {}
            }
        }

        app.rebuild()
        let ring = FocusManager.allFocusableNodes(root: app.rootNode)
        XCTAssertEqual(ring.count, 1, ".focusable(false) must remove the wrapped control from the ring")
        XCTAssertNotNil(app.focusedNode?[.action], "Only the Button should be focusable")
    }

    // MARK: - Resolving through passthrough wrappers

    func testFocusableThroughWrapperAddsNoDuplicateStop() {
        // `.focusable()` applied *after* another modifier must still resolve to
        // the control underneath, not stamp the invisible wrapper between them.
        let app = makeApp {
            VStack {
                Button("ok") {}
                    .onKeyPress { _ in .ignored }
                    .focusable()
                Button("cancel") {}
            }
        }

        app.rebuild()
        let ring = FocusManager.allFocusableNodes(root: app.rootNode)
        XCTAssertEqual(
            ring.count, 2,
            ".focusable() reaching a control through a wrapper must not add a second stop")
    }

    func testFocusableFalseThroughWrapperRemovesControlFromRing() {
        var text = ""
        let app = makeApp {
            VStack {
                TextField("name", get: { text }, set: { text = $0 })
                    .onKeyPress { _ in .ignored }
                    .focusable(false)
                Button("ok") {}
            }
        }

        app.rebuild()
        let ring = FocusManager.allFocusableNodes(root: app.rootNode)
        XCTAssertEqual(
            ring.count, 1,
            ".focusable(false) must reach the control through a wrapper and remove it")
    }

    func testFocusableThroughEnvironmentModifierAddsNoDuplicateStop() {
        // Styling modifiers are passthrough wrappers too.
        let app = makeApp {
            VStack {
                Button("ok") {}.bold().focusable()
                Button("cancel") {}
            }
        }

        app.rebuild()
        let ring = FocusManager.allFocusableNodes(root: app.rootNode)
        XCTAssertEqual(ring.count, 2, ".focusable() through .bold() must not add a second stop")
    }

    // MARK: - Focus survives ring membership changes above it

    func testFocusStaysOnSameNodeWhenEarlierRingEntryDisappears() {
        var showFirst = true
        var text = ""
        var pressed = false
        let app = makeApp {
            VStack {
                if showFirst {
                    Button("first") {}
                }
                TextField("name", get: { text }, set: { text = $0 })
                Button("submit") { pressed = true }
            }
        }

        app.rebuild()
        XCTAssertTrue(app.handleKey(KeyEvent(key: .tab)))
        XCTAssertEqual(app.focusedIndex, 1, "Tab should land on the TextField")

        // The Button above the field leaves the tree; focus must follow the
        // field to its new position instead of sticking to the raw index.
        showFirst = false
        app.rebuild()

        XCTAssertEqual(app.focusedIndex, 0, "Focus should re-bind to the TextField's new index")
        XCTAssertNotNil(app.focusedNode?[.textInputHandler], "The TextField should still be focused")

        XCTAssertTrue(app.handleKey(KeyEvent(key: .char(" "))))
        XCTAssertEqual(text, " ", "Typed characters must reach the field")
        XCTAssertFalse(pressed, "The Button must not receive the stray key")
    }
}

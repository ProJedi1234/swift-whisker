import XCTest

@testable import Whisker

final class KeyEventTests: XCTestCase {

    /// Records the keys seen by a `.onKeyPress` handler and controls its return value.
    private final class KeyRecorder {
        var keys: [Key] = []
        var result: KeyPressResult = .handled
    }

    private struct ProbeView: View {
        var body: some View {
            Text("probe")
        }
    }

    private func makeApp(
        backend: TestBackend = TestBackend(size: Size(width: 40, height: 10)),
        @ViewBuilder rootView: @escaping () -> some View
    ) -> Application {
        Application(mode: .fullscreen, backend: backend, rootView: rootView)
    }

    override func tearDown() {
        Application.shared = nil
        NodeContext.current = nil
        super.tearDown()
    }

    // MARK: - (a) Focusable composite captures keys

    func testFocusableCompositeOnKeyPressCapturesKeys() {
        let recorder = KeyRecorder()
        let app = makeApp {
            ProbeView()
                .focusable()
                .onKeyPress { event in
                    recorder.keys.append(event.key)
                    return recorder.result
                }
        }

        app.rebuild()
        XCTAssertNotNil(app.focusedNode, "Focusable composite should join the focus ring")
        XCTAssertTrue(app.focusedNode?.isFocusable ?? false)

        XCTAssertTrue(app.handleKey(KeyEvent(key: .up)))
        XCTAssertTrue(app.handleKey(KeyEvent(key: .down)))
        XCTAssertTrue(app.handleKey(KeyEvent(key: .escape)))
        XCTAssertTrue(app.handleKey(KeyEvent(key: .enter)))

        XCTAssertEqual(recorder.keys, [.up, .down, .escape, .enter])
    }

    func testOnKeyPressBeforeFocusableAlsoCapturesKeys() {
        // The reversed modifier order must behave identically — the pairing
        // is order-independent, not a silent no-op.
        let recorder = KeyRecorder()
        let app = makeApp {
            ProbeView()
                .onKeyPress { event in
                    recorder.keys.append(event.key)
                    return recorder.result
                }
                .focusable()
        }

        app.rebuild()
        XCTAssertNotNil(app.focusedNode, "Focusable composite should join the focus ring")

        XCTAssertTrue(app.handleKey(KeyEvent(key: .up)))
        XCTAssertTrue(app.handleKey(KeyEvent(key: .enter)))

        XCTAssertEqual(recorder.keys, [.up, .enter], ".onKeyPress applied before .focusable() must still fire")
    }

    func testUnconsumedEscapeIsDropped() {
        let recorder = KeyRecorder()
        recorder.result = .ignored
        let app = makeApp {
            ProbeView()
                .focusable()
                .onKeyPress { event in
                    recorder.keys.append(event.key)
                    return recorder.result
                }
        }

        app.rebuild()

        XCTAssertFalse(
            app.handleKey(KeyEvent(key: .escape)),
            "Escape not consumed by any handler should be dropped")
        XCTAssertEqual(recorder.keys, [.escape], "Handler should still have been offered escape")
    }

    // MARK: - (b) Returning .ignored falls back to focus traversal

    func testReturningIgnoredOnUpStillMovesFocus() {
        let recorder = KeyRecorder()
        recorder.result = .ignored
        var text = ""
        let app = makeApp {
            VStack {
                TextField("name", get: { text }, set: { text = $0 })
                ProbeView()
                    .focusable()
                    .onKeyPress { event in
                        recorder.keys.append(event.key)
                        return recorder.result
                    }
            }
        }

        app.rebuild()
        XCTAssertEqual(app.focusedIndex, 0, "Focus should start on the TextField")

        XCTAssertTrue(app.handleKey(KeyEvent(key: .tab)))
        XCTAssertEqual(app.focusedIndex, 1, "Tab should move focus to the composite")
        XCTAssertEqual(recorder.keys, [], "Handler is not on the TextField's ancestor chain")

        XCTAssertTrue(app.handleKey(KeyEvent(key: .up)))
        XCTAssertEqual(recorder.keys, [.up], "Handler should be offered the key first")
        XCTAssertEqual(
            app.focusedIndex, 0,
            "Unconsumed .up should fall back to moving focus to the previous node")
    }

    // MARK: - (c) TextField behavior is unchanged

    func testTextFieldStillReceivesCharsAndArrows() {
        var text = ""
        let app = makeApp {
            TextField("name", get: { text }, set: { text = $0 })
        }

        app.rebuild()
        XCTAssertNotNil(app.focusedNode)

        XCTAssertTrue(app.handleKey(KeyEvent(key: .char("A"))))
        XCTAssertTrue(app.handleKey(KeyEvent(key: .char("B"))))
        XCTAssertEqual(text, "AB")

        XCTAssertTrue(app.handleKey(KeyEvent(key: .left)))
        XCTAssertTrue(app.handleKey(KeyEvent(key: .char("C"))))
        XCTAssertEqual(text, "ACB")

        XCTAssertTrue(app.handleKey(KeyEvent(key: .right)))
        XCTAssertTrue(app.handleKey(KeyEvent(key: .backspace)))
        XCTAssertEqual(text, "AC")
    }

    func testTextFieldUpStillMovesFocusAcrossFields() {
        var first = ""
        var second = ""
        let app = makeApp {
            VStack {
                TextField("first", get: { first }, set: { first = $0 })
                TextField("second", get: { second }, set: { second = $0 })
            }
        }

        app.rebuild()
        XCTAssertEqual(app.focusedIndex, 0)

        XCTAssertTrue(app.handleKey(KeyEvent(key: .down)))
        XCTAssertEqual(app.focusedIndex, 1, ".down should still traverse focus")

        XCTAssertTrue(app.handleKey(KeyEvent(key: .up)))
        XCTAssertEqual(app.focusedIndex, 0, ".up should still traverse focus")
    }

    // MARK: - (d) Tab traversal across a mixed focus ring

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

    // MARK: - (e) Multi-node routing

    func testChildHandlerRunsBeforeAncestorAndHandledStopsBubbling() {
        let inner = KeyRecorder()
        let outer = KeyRecorder()
        var order: [String] = []
        let app = makeApp {
            VStack {
                ProbeView()
                    .focusable()
                    .onKeyPress { event in
                        order.append("inner")
                        inner.keys.append(event.key)
                        return inner.result
                    }
            }
            .onKeyPress { event in
                order.append("outer")
                outer.keys.append(event.key)
                return outer.result
            }
        }

        app.rebuild()
        XCTAssertTrue(app.handleKey(KeyEvent(key: .enter)))

        XCTAssertEqual(order, ["inner"], "The focused node's handler runs first")
        XCTAssertEqual(outer.keys, [], ".handled must stop the event bubbling to the ancestor")
    }

    func testIgnoredChildBubblesToAncestorHandler() {
        let inner = KeyRecorder()
        inner.result = .ignored
        let outer = KeyRecorder()
        var order: [String] = []
        let app = makeApp {
            VStack {
                ProbeView()
                    .focusable()
                    .onKeyPress { event in
                        order.append("inner")
                        inner.keys.append(event.key)
                        return inner.result
                    }
            }
            .onKeyPress { event in
                order.append("outer")
                outer.keys.append(event.key)
                return outer.result
            }
        }

        app.rebuild()
        XCTAssertTrue(app.handleKey(KeyEvent(key: .enter)))

        XCTAssertEqual(order, ["inner", "outer"], "An ignored key bubbles child-first to the ancestor")
        XCTAssertEqual(outer.keys, [.enter])
    }

    func testAllIgnoredHandlersFallBackToTraversal() {
        let inner = KeyRecorder()
        inner.result = .ignored
        let outer = KeyRecorder()
        outer.result = .ignored
        var text = ""
        let app = makeApp {
            VStack {
                TextField("name", get: { text }, set: { text = $0 })
                ProbeView()
                    .focusable()
                    .onKeyPress { event in
                        inner.keys.append(event.key)
                        return inner.result
                    }
            }
            .onKeyPress { event in
                outer.keys.append(event.key)
                return outer.result
            }
        }

        app.rebuild()
        XCTAssertTrue(app.handleKey(KeyEvent(key: .tab)))
        XCTAssertEqual(app.focusedIndex, 1, "Focus starts on the composite")

        XCTAssertTrue(app.handleKey(KeyEvent(key: .up)))
        XCTAssertEqual(inner.keys, [.up], "The composite's own handler sees only its own keys")
        XCTAssertEqual(
            outer.keys, [.tab, .up],
            "The ancestor wraps the whole stack, so it is offered the TextField's tab too")
        XCTAssertEqual(app.focusedIndex, 0, "All-ignored .up still falls back to focus traversal")
    }

    func testPrintableInputBypassesAncestorOnKeyPress() {
        let ancestor = KeyRecorder()
        var text = ""
        let app = makeApp {
            VStack {
                TextField("name", get: { text }, set: { text = $0 })
            }
            .onKeyPress { event in
                ancestor.keys.append(event.key)
                return ancestor.result
            }
        }

        app.rebuild()
        XCTAssertTrue(app.handleKey(KeyEvent(key: .char("A"))))
        XCTAssertTrue(app.handleKey(KeyEvent(key: .char("B"))))

        XCTAssertEqual(text, "AB", "Printable input must reach the focused field")
        XCTAssertEqual(
            ancestor.keys, [], "A focused text field consumes printable keys before they bubble")
    }

    // MARK: - (f) Focus survives ring membership changes above it

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

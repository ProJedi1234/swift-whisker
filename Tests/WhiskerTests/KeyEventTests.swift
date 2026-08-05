import XCTest

@testable import Whisker

/// How key events are routed to handlers, and what falls back to default handling.
final class KeyEventTests: KeyEventTestCase {

    // MARK: - Focusable composite captures keys

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

    // MARK: - Returning .ignored falls back to focus traversal

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

    // MARK: - TextField behavior is unchanged

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

    // MARK: - Multi-node routing

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

}

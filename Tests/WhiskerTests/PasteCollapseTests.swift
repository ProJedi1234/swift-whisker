import XCTest
@testable import Whisker

final class PasteCollapseTests: XCTestCase {
    func testWordCountSplitsOnWhitespace() {
        XCTAssertEqual(PasteCollapse.wordCount(""), 0)
        XCTAssertEqual(PasteCollapse.wordCount("  one  two\nthree\t"), 3)
        XCTAssertEqual(PasteCollapse.wordCount("single"), 1)
    }

    func testShouldCollapseAtThreshold() {
        let words = (1...50).map { "w\($0)" }.joined(separator: " ")
        XCTAssertTrue(PasteCollapse.shouldCollapse(words))
        XCTAssertFalse(PasteCollapse.shouldCollapse("short paste"))
    }

    func testLabelSingularAndPlural() {
        XCTAssertEqual(PasteCollapse.label(forPayload: "hello"), "[Pasted 1 word]")
        XCTAssertEqual(PasteCollapse.label(forPayload: "a b c"), "[Pasted 3 words]")
    }

    func testExpandAndVisualRoundTrip() {
        var display = "hello "
        var cursor = display.count
        var store: [String: String] = [:]
        let payload = (1...50).map { "w\($0)" }.joined(separator: " ")
        _ = PasteCollapse.insertCollapsedPaste(
            payload,
            into: &display,
            cursor: &cursor,
            store: &store
        )
        display += " world"

        XCTAssertEqual(
            PasteCollapse.expand(displayText: display, store: store),
            "hello \(payload) world"
        )
        XCTAssertEqual(
            PasteCollapse.visualString(displayText: display, store: store),
            "hello [Pasted 50 words] world"
        )
        XCTAssertEqual(store.count, 1)
    }

    func testAtomicBackspaceDeletesSentinel() {
        var display = "ab"
        var cursor = display.count
        var store: [String: String] = [:]
        let payload = (1...50).map { "w\($0)" }.joined(separator: " ")
        _ = PasteCollapse.insertCollapsedPaste(
            payload,
            into: &display,
            cursor: &cursor,
            store: &store
        )
        display += "cd"
        cursor = display.count - 2 // after sentinel, before "cd"

        PasteCollapse.backspace(displayText: &display, cursor: &cursor, store: &store)

        XCTAssertEqual(display, "abcd")
        XCTAssertEqual(cursor, 2)
        XCTAssertTrue(store.isEmpty)
        XCTAssertEqual(PasteCollapse.expand(displayText: display, store: store), "abcd")
    }

    func testAtomicDeleteForwardRemovesSentinel() {
        var display = "ab"
        var cursor = display.count
        var store: [String: String] = [:]
        let payload = (1...50).map { "w\($0)" }.joined(separator: " ")
        _ = PasteCollapse.insertCollapsedPaste(
            payload,
            into: &display,
            cursor: &cursor,
            store: &store
        )
        display += "cd"
        cursor = 2 // at start of sentinel

        PasteCollapse.deleteForward(displayText: &display, cursor: &cursor, store: &store)

        XCTAssertEqual(display, "abcd")
        XCTAssertEqual(cursor, 2)
        XCTAssertTrue(store.isEmpty)
    }

    func testArrowKeysJumpOverSentinel() {
        var display = "x"
        var cursor = display.count
        var store: [String: String] = [:]
        let payload = (1...50).map { "w\($0)" }.joined(separator: " ")
        _ = PasteCollapse.insertCollapsedPaste(
            payload,
            into: &display,
            cursor: &cursor,
            store: &store
        )
        // cursor is after sentinel
        PasteCollapse.moveLeft(cursor: &cursor, in: display)
        XCTAssertEqual(cursor, 1) // before sentinel (after "x")

        PasteCollapse.moveRight(cursor: &cursor, in: display)
        XCTAssertEqual(cursor, display.count)
    }

    func testVisualWidthCountsLabelNotSentinel() {
        var display = "hi "
        var cursor = display.count
        var store: [String: String] = [:]
        let payload = (1...50).map { "w\($0)" }.joined(separator: " ")
        _ = PasteCollapse.insertCollapsedPaste(
            payload,
            into: &display,
            cursor: &cursor,
            store: &store
        )

        let expected = terminalTextWidth("hi [Pasted 50 words]", replacingControlCharacters: true)
        let actual = PasteCollapse.visualWidth(
            displayText: display,
            store: store,
            upToCharacterOffset: display.count
        )
        XCTAssertEqual(actual, expected)
    }
}

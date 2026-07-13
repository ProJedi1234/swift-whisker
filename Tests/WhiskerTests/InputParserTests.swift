import XCTest

@testable import Whisker

final class InputParserTests: XCTestCase {
    private enum EventValue: Equatable {
        case key(Key, KeyModifiers)
        case text(String)
        case paste(String)
    }

    private let clock = ContinuousClock()

    func testSingleFeedEmitsMultipleOrderedEvents() {
        var parser = InputParser()
        let input = Array("hello\u{1b}[A🙂".utf8)

        XCTAssertEqual(values(parser.feed(input, at: clock.now)), [
            .text("hello"),
            .key(.up, []),
            .text("🙂")
        ])
    }

    func testUTF8AndEscapeSequencesAreStableAtEveryByteBoundary() {
        let input = Array("café\u{1b}[D🙂\u{1b}[3~!".utf8)
        let expected = parse(input)

        for boundary in 0...input.count {
            var parser = InputParser()
            let now = clock.now
            var events = parser.feed(Array(input[..<boundary]), at: now)
            events += parser.feed(Array(input[boundary...]), at: now)
            XCTAssertEqual(normalized(values(events)), expected, "boundary \(boundary)")
        }
    }

    func testUTF8CanArriveOneByteAtATime() {
        let input = Array("e\u{301}—👨‍👩‍👧‍👦".utf8)
        var parser = InputParser()
        let now = clock.now
        let events = input.flatMap { parser.feed([$0], at: now) }

        XCTAssertEqual(normalized(values(events)), [.text("é—👨‍👩‍👧‍👦")])
    }

    func testLoneEscapeWaitsForConfiguredDeadline() {
        var parser = InputParser(escapeTimeout: .milliseconds(50))
        let now = clock.now

        XCTAssertTrue(parser.feed([0x1b], at: now).isEmpty)
        XCTAssertNotNil(parser.nextDeadline)
        XCTAssertTrue(parser.flushExpired(at: now.advanced(by: .milliseconds(49))).isEmpty)
        XCTAssertEqual(
            values(parser.flushExpired(at: now.advanced(by: .milliseconds(50)))),
            [.key(.escape, [])]
        )
        XCTAssertNil(parser.nextDeadline)
    }

    func testContinuationBeforeEscapeDeadlineProducesArrow() {
        var parser = InputParser()
        let now = clock.now

        XCTAssertTrue(parser.feed([0x1b], at: now).isEmpty)
        XCTAssertEqual(
            values(parser.feed(Array("[A".utf8), at: now.advanced(by: .milliseconds(49)))),
            [.key(.up, [])]
        )
    }

    func testContinuationAfterEscapeDeadlineProducesSeparateEvents() {
        var parser = InputParser()
        let now = clock.now

        XCTAssertTrue(parser.feed([0x1b], at: now).isEmpty)
        XCTAssertEqual(
            values(parser.feed(Array("x".utf8), at: now.advanced(by: .milliseconds(51)))),
            [.key(.escape, []), .text("x")]
        )
    }

    func testAltModifiedUnicodeCanBeFragmented() {
        var parser = InputParser()
        let now = clock.now
        let input = Array("\u{1b}é".utf8)

        XCTAssertTrue(parser.feed(Array(input.prefix(2)), at: now).isEmpty)
        XCTAssertEqual(
            values(parser.feed(Array(input.dropFirst(2)), at: now)),
            [.key(.char("é"), .alt)]
        )
    }

    func testCommonCSIKeys() {
        var parser = InputParser()
        let now = clock.now
        let input = Array("\u{1b}[3~\u{1b}[5~\u{1b}[6~\u{1b}[1~\u{1b}[4~\u{1b}[15~".utf8)

        XCTAssertEqual(values(parser.feed(input, at: now)), [
            .key(.delete, []),
            .key(.pageUp, []),
            .key(.pageDown, []),
            .key(.home, []),
            .key(.end, []),
            .key(.f(5), [])
        ])
    }

    func testBracketedPasteIsAtomicAndTreatsEscapeSequencesAsText() {
        let payload = "first\n\u{1b}[A\t🙂"
        let input = Array("\u{1b}[200~\(payload)\u{1b}[201~after".utf8)
        var parser = InputParser()
        let now = clock.now
        let events = input.flatMap { parser.feed([$0], at: now) }

        XCTAssertEqual(normalized(values(events)), [.paste(payload), .text("after")])
    }

    func testLargeBracketedPasteExceedsReadBuffer() {
        let payload = String(repeating: "A🙂\n", count: 4_000)
        let input = Array("\u{1b}[200~\(payload)\u{1b}[201~".utf8)
        var parser = InputParser()
        let now = clock.now
        var events: [TerminalEvent] = []

        for start in stride(from: 0, to: input.count, by: 4096) {
            events += parser.feed(Array(input[start..<min(start + 4096, input.count)]), at: now)
        }

        XCTAssertEqual(values(events), [.paste(payload)])
    }

    func testLargeOrdinaryTextExceedsReadBuffer() {
        let payload = String(repeating: "A long Unicode story 🙂 ", count: 2_000)
        let input = Array(payload.utf8)
        var parser = InputParser()
        let now = clock.now
        var events: [TerminalEvent] = []

        for start in stride(from: 0, to: input.count, by: 4096) {
            events += parser.feed(Array(input[start..<min(start + 4096, input.count)]), at: now)
        }

        XCTAssertEqual(normalized(values(events)), [.text(payload)])
    }

    func testMalformedUTF8IsRepairedWithoutStalling() {
        var parser = InputParser()
        let events = parser.feed([0xf0, 0x28, 0x8c, 0x28, 0x61], at: clock.now)

        XCTAssertEqual(values(events), [.text("�(�(a")])
    }

    func testMalformedUTF8InsidePasteIsRepairedAsPasteText() {
        var parser = InputParser()
        var input = Array("\u{1b}[200~".utf8)
        input += [0xf0, 0x28, 0x8c]
        input += Array("\u{1b}[201~".utf8)

        XCTAssertEqual(values(parser.feed(input, at: clock.now)), [.paste("�(�")])
    }

    func testFinishFlushesIncompleteUTF8AndPaste() {
        var textParser = InputParser()
        _ = textParser.feed([0xf0, 0x9f], at: clock.now)
        XCTAssertEqual(values(textParser.finish()), [.text("�")])

        var pasteParser = InputParser()
        _ = pasteParser.feed(Array("\u{1b}[200~unfinished".utf8), at: clock.now)
        XCTAssertEqual(values(pasteParser.finish()), [.paste("unfinished")])
    }

    private func parse(_ bytes: [UInt8]) -> [EventValue] {
        var parser = InputParser()
        return normalized(values(parser.feed(bytes, at: clock.now)))
    }

    private func values(_ events: [TerminalEvent]) -> [EventValue] {
        events.compactMap { event in
            switch event {
            case .key(let event): return .key(event.key, event.modifiers)
            case .text(let text): return .text(text)
            case .paste(let text): return .paste(text)
            case .resize, .mouse: return nil
            }
        }
    }

    private func normalized(_ events: [EventValue]) -> [EventValue] {
        events.reduce(into: []) { result, event in
            if case .text(let next) = event,
               case .text(let previous)? = result.last {
                result[result.count - 1] = .text(previous + next)
            } else {
                result.append(event)
            }
        }
    }
}

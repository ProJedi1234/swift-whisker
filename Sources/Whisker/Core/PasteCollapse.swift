/// Collapses large pastes into atomic display markers while keeping bindings expanded.
enum PasteCollapse {
    /// Pastes with at least this many whitespace-separated words become markers.
    static let defaultWordThreshold = 50

    static let sentinelStart: Character = "\u{E000}"
    static let sentinelEnd: Character = "\u{E001}"

    /// A contiguous sentinel span in display text: `\u{E000}` + 8 hex id + `\u{E001}`.
    struct SentinelSpan {
        let range: Range<String.Index>
        /// Character offset of `range.lowerBound` from `startIndex`.
        let startOffset: Int
        /// Character length of the sentinel span.
        let length: Int
        let id: String

        var endOffset: Int { startOffset + length }
    }

    // MARK: - Word counting & labels

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace }.count
    }

    static func shouldCollapse(_ text: String, threshold: Int = defaultWordThreshold) -> Bool {
        wordCount(text) >= threshold
    }

    static func label(forPayload payload: String) -> String {
        let count = wordCount(payload)
        return count == 1 ? "[Pasted 1 word]" : "[Pasted \(count) words]"
    }

    // MARK: - Sentinels

    static func makeID() -> String {
        String(format: "%08x", UInt32.random(in: 0...UInt32.max))
    }

    static func makeSentinel(id: String) -> String {
        "\(sentinelStart)\(id)\(sentinelEnd)"
    }

    /// Scans `displayText` for well-formed sentinel spans.
    static func sentinelSpans(in displayText: String) -> [SentinelSpan] {
        var spans: [SentinelSpan] = []
        var offset = 0
        var index = displayText.startIndex

        while index < displayText.endIndex {
            let character = displayText[index]
            if character == sentinelStart {
                let startIndex = index
                let startOffset = offset
                displayText.formIndex(after: &index)
                offset += 1

                var idChars: [Character] = []
                while index < displayText.endIndex,
                      displayText[index] != sentinelEnd,
                      idChars.count < 8
                {
                    idChars.append(displayText[index])
                    displayText.formIndex(after: &index)
                    offset += 1
                }

                if index < displayText.endIndex,
                   displayText[index] == sentinelEnd,
                   idChars.count == 8,
                   idChars.allSatisfy({ $0.isHexDigit })
                {
                    displayText.formIndex(after: &index)
                    offset += 1
                    let endIndex = index
                    spans.append(
                        SentinelSpan(
                            range: startIndex..<endIndex,
                            startOffset: startOffset,
                            length: offset - startOffset,
                            id: String(idChars)
                        )
                    )
                    continue
                }

                // Malformed — treat as ordinary characters already consumed.
                continue
            }

            displayText.formIndex(after: &index)
            offset += 1
        }

        return spans
    }

    static func span(atOffset offset: Int, in displayText: String) -> SentinelSpan? {
        sentinelSpans(in: displayText).first {
            offset >= $0.startOffset && offset < $0.endOffset
        }
    }

    static func spanEnding(at offset: Int, in displayText: String) -> SentinelSpan? {
        sentinelSpans(in: displayText).first { $0.endOffset == offset }
    }

    static func spanStarting(at offset: Int, in displayText: String) -> SentinelSpan? {
        sentinelSpans(in: displayText).first { $0.startOffset == offset }
    }

    // MARK: - Expand / visual

    static func expand(displayText: String, store: [String: String]) -> String {
        var result = ""
        var offset = 0
        var index = displayText.startIndex
        let spans = sentinelSpans(in: displayText)
        var spanIndex = 0

        while index < displayText.endIndex {
            if spanIndex < spans.count, spans[spanIndex].startOffset == offset {
                let span = spans[spanIndex]
                result += store[span.id] ?? ""
                index = span.range.upperBound
                offset = span.endOffset
                spanIndex += 1
            } else {
                result.append(displayText[index])
                displayText.formIndex(after: &index)
                offset += 1
            }
        }

        return result
    }

    static func visualString(displayText: String, store: [String: String]) -> String {
        var result = ""
        var offset = 0
        var index = displayText.startIndex
        let spans = sentinelSpans(in: displayText)
        var spanIndex = 0

        while index < displayText.endIndex {
            if spanIndex < spans.count, spans[spanIndex].startOffset == offset {
                let span = spans[spanIndex]
                if let payload = store[span.id] {
                    result += label(forPayload: payload)
                }
                index = span.range.upperBound
                offset = span.endOffset
                spanIndex += 1
            } else {
                result.append(displayText[index])
                displayText.formIndex(after: &index)
                offset += 1
            }
        }

        return result
    }

    /// Visual column width of the display prefix up to `characterOffset`.
    static func visualWidth(
        displayText: String,
        store: [String: String],
        upToCharacterOffset characterOffset: Int,
        replacingControlCharacters: Bool = true
    ) -> Int {
        let clamped = min(max(0, characterOffset), displayText.count)
        var width = 0
        var offset = 0
        var index = displayText.startIndex
        let spans = sentinelSpans(in: displayText)
        var spanIndex = 0

        while offset < clamped, index < displayText.endIndex {
            if spanIndex < spans.count, spans[spanIndex].startOffset == offset {
                let span = spans[spanIndex]
                if clamped <= span.startOffset {
                    break
                }
                // Cursor inside a sentinel (shouldn't happen with atomic nav) —
                // count full label once we enter the span.
                if let payload = store[span.id] {
                    width += terminalTextWidth(
                        label(forPayload: payload),
                        replacingControlCharacters: replacingControlCharacters
                    )
                }
                index = span.range.upperBound
                offset = span.endOffset
                spanIndex += 1
                continue
            }

            let character = displayText[index]
            let rendered = replacingControlCharacters
                ? terminalSafeCharacter(character)
                : character
            width += terminalCellWidth(rendered)
            displayText.formIndex(after: &index)
            offset += 1
        }

        return width
    }

    // MARK: - Atomic editing

    /// Moves the cursor left across a sentinel as one unit if adjacent.
    static func moveLeft(cursor: inout Int, in displayText: String) {
        guard cursor > 0 else { return }
        if let span = spanEnding(at: cursor, in: displayText) {
            cursor = span.startOffset
        } else {
            cursor -= 1
        }
    }

    /// Moves the cursor right across a sentinel as one unit if adjacent.
    static func moveRight(cursor: inout Int, in displayText: String) {
        let maxOffset = displayText.count
        guard cursor < maxOffset else { return }
        if let span = spanStarting(at: cursor, in: displayText) {
            cursor = span.endOffset
        } else {
            cursor += 1
        }
    }

    /// Deletes the sentinel ending at `cursor` (backspace), or one character.
    /// Returns the removed paste id if a sentinel was deleted.
    @discardableResult
    static func backspace(
        displayText: inout String,
        cursor: inout Int,
        store: inout [String: String]
    ) -> String? {
        guard cursor > 0 else { return nil }
        if let span = spanEnding(at: cursor, in: displayText) {
            let id = span.id
            displayText.removeSubrange(span.range)
            store.removeValue(forKey: id)
            cursor = span.startOffset
            return id
        }

        let index = displayText.index(displayText.startIndex, offsetBy: cursor - 1)
        displayText.remove(at: index)
        cursor -= 1
        return nil
    }

    /// Deletes the sentinel starting at `cursor` (forward delete), or one character.
    @discardableResult
    static func deleteForward(
        displayText: inout String,
        cursor: inout Int,
        store: inout [String: String]
    ) -> String? {
        guard cursor < displayText.count else { return nil }
        if let span = spanStarting(at: cursor, in: displayText) {
            let id = span.id
            displayText.removeSubrange(span.range)
            store.removeValue(forKey: id)
            return id
        }

        let index = displayText.index(displayText.startIndex, offsetBy: cursor)
        displayText.remove(at: index)
        return nil
    }

    /// Inserts raw text at the cursor into `displayText`.
    static func insertRaw(
        _ inserted: String,
        into displayText: inout String,
        cursor: inout Int
    ) {
        let insertionIndex = displayText.index(displayText.startIndex, offsetBy: cursor)
        displayText.insert(contentsOf: inserted, at: insertionIndex)
        cursor += inserted.count
    }

    /// Inserts a collapsed paste sentinel at the cursor and stores the payload.
    static func insertCollapsedPaste(
        _ payload: String,
        into displayText: inout String,
        cursor: inout Int,
        store: inout [String: String]
    ) -> String {
        let id = makeID()
        store[id] = payload
        let sentinel = makeSentinel(id: id)
        insertRaw(sentinel, into: &displayText, cursor: &cursor)
        return id
    }
}

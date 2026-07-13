struct InputParser {
    private static let bracketedPasteStart = Array("\u{1b}[200~".utf8)
    private static let bracketedPasteEnd = Array("\u{1b}[201~".utf8)
    /// Default ceiling for a single bracketed-paste payload (1 MiB).
    static let defaultMaxPasteByteCount = 1_048_576
    private static let tildeKeys: [Int: Key] = [
        1: .home,
        3: .delete,
        4: .end,
        5: .pageUp,
        6: .pageDown,
        7: .home,
        8: .end,
        11: .f(1),
        12: .f(2),
        13: .f(3),
        14: .f(4),
        15: .f(5),
        17: .f(6),
        18: .f(7),
        19: .f(8),
        20: .f(9),
        21: .f(10),
        23: .f(11),
        24: .f(12)
    ]

    let escapeTimeout: Duration
    /// Hard limit on buffered paste bytes; overflow is truncated and discarded until the end marker.
    let maxPasteByteCount: Int

    private var buffer: [UInt8] = []
    private var pasteBuffer: [UInt8]?
    /// True after `pasteBuffer` hits `maxPasteByteCount`; remaining paste bytes are dropped.
    private var discardingPaste = false
    private(set) var nextDeadline: ContinuousClock.Instant?

    init(
        escapeTimeout: Duration = .milliseconds(50),
        maxPasteByteCount: Int = InputParser.defaultMaxPasteByteCount
    ) {
        self.escapeTimeout = max(.zero, escapeTimeout)
        self.maxPasteByteCount = max(0, maxPasteByteCount)
    }

    mutating func feed(
        _ bytes: [UInt8],
        at now: ContinuousClock.Instant
    ) -> [TerminalEvent] {
        var events = flushExpired(at: now)
        buffer.append(contentsOf: bytes)
        events.append(contentsOf: parseAvailable(at: now))
        return events
    }

    mutating func flushExpired(at now: ContinuousClock.Instant) -> [TerminalEvent] {
        guard let deadline = nextDeadline, deadline <= now,
              buffer.first == 0x1b, buffer.count == 1
        else { return [] }

        buffer.removeFirst()
        nextDeadline = nil
        return [.key(KeyEvent(key: .escape))]
    }

    mutating func finish() -> [TerminalEvent] {
        var events = parseAvailable(at: ContinuousClock().now)

        if var pasteBuffer {
            if !discardingPaste {
                appendPasteBytes(Array(buffer), to: &pasteBuffer)
            }
            buffer.removeAll(keepingCapacity: true)
            self.pasteBuffer = nil
            discardingPaste = false
            nextDeadline = nil
            events.append(.paste(String(decoding: pasteBuffer, as: UTF8.self)))
            return events
        }

        if discardingPaste {
            buffer.removeAll(keepingCapacity: true)
            discardingPaste = false
            nextDeadline = nil
            return events
        }

        guard !buffer.isEmpty else { return events }

        if buffer[0] == 0x1b {
            events.append(.key(KeyEvent(key: .escape)))
            // A truncated CSI sequence is terminal protocol data, not user text.
            if buffer.count > 1, buffer[1] != UInt8(ascii: "[") {
                let remainder = buffer.dropFirst()
                events.append(.text(String(decoding: remainder, as: UTF8.self)))
            }
        } else {
            events.append(.text(String(decoding: buffer, as: UTF8.self)))
        }

        buffer.removeAll(keepingCapacity: true)
        nextDeadline = nil
        return events
    }

    private mutating func parseAvailable(at now: ContinuousClock.Instant) -> [TerminalEvent] {
        var events: [TerminalEvent] = []
        var pendingText = ""

        func flushText() {
            guard !pendingText.isEmpty else { return }
            events.append(.text(pendingText))
            pendingText.removeAll(keepingCapacity: true)
        }

        while !buffer.isEmpty {
            if pasteBuffer != nil || discardingPaste {
                flushText()
                guard consumePasteIfComplete(into: &events) else { break }
                continue
            }

            let byte = buffer[0]
            if byte == 0x1b {
                flushText()
                guard parseEscape(at: now, into: &events) else { break }
                continue
            }

            if byte < 0x20 || byte == 0x7f {
                flushText()
                buffer.removeFirst()
                if let event = controlEvent(for: byte) {
                    events.append(event)
                }
                continue
            }

            let decoded = decodeTextPrefix()
            pendingText.append(decoded.text)
            buffer.removeFirst(decoded.consumedCount)
            if decoded.needsMoreBytes {
                flushText()
                return events
            }
        }

        flushText()
        return events
    }

    private func decodeTextPrefix() -> (
        text: String,
        consumedCount: Int,
        needsMoreBytes: Bool
    ) {
        var text = ""
        var index = 0

        while index < buffer.count {
            let byte = buffer[index]
            if byte == 0x1b || byte < 0x20 || byte == 0x7f { break }

            switch decodeScalar(in: buffer[index...]) {
            case .complete(let scalar, let length):
                text.unicodeScalars.append(scalar)
                index += length
            case .invalid:
                text.append("\u{fffd}")
                index += 1
            case .incomplete:
                return (text, index, true)
            }
        }

        return (text, index, false)
    }

    private mutating func parseEscape(
        at now: ContinuousClock.Instant,
        into events: inout [TerminalEvent]
    ) -> Bool {
        guard buffer.count > 1 else {
            if nextDeadline == nil {
                nextDeadline = now.advanced(by: escapeTimeout)
            }
            return false
        }

        nextDeadline = nil

        if buffer[1] == UInt8(ascii: "[") {
            guard let finalIndex = csiFinalIndex() else { return false }
            let sequence = Array(buffer[...finalIndex])
            buffer.removeFirst(finalIndex + 1)

            if sequence == Self.bracketedPasteStart {
                beginPasteMode()
            } else if let event = event(forCSI: sequence) {
                events.append(event)
            }
            return true
        }

        switch decodeScalar(in: buffer.dropFirst()) {
        case .complete(let scalar, let length):
            guard scalar.properties.generalCategory != .control else {
                buffer.removeFirst()
                events.append(.key(KeyEvent(key: .escape)))
                return true
            }
            buffer.removeFirst(length + 1)
            events.append(.key(KeyEvent(
                key: .char(Character(String(scalar))),
                modifiers: .alt
            )))
            return true
        case .invalid:
            buffer.removeFirst()
            events.append(.key(KeyEvent(key: .escape)))
            return true
        case .incomplete:
            return false
        }
    }

    private func csiFinalIndex() -> Int? {
        for index in 2..<buffer.count {
            let byte = buffer[index]
            if (0x40...0x7e).contains(byte) { return index }
            // Parameter and intermediate bytes occupy 0x20...0x3f. Consume malformed
            // protocol input through the offending byte so it cannot wedge the parser.
            if !(0x20...0x3f).contains(byte) { return index }
        }
        return nil
    }

    private mutating func beginPasteMode() {
        var initial: [UInt8] = []
        if maxPasteByteCount > 0 {
            initial.reserveCapacity(min(4_096, maxPasteByteCount))
        }
        pasteBuffer = initial
        discardingPaste = false
    }

    private mutating func consumePasteIfComplete(into events: inout [TerminalEvent]) -> Bool {
        if let markerIndex = buffer.firstRange(of: Self.bracketedPasteEnd)?.lowerBound {
            if var pasteBuffer {
                if !discardingPaste {
                    appendPasteBytes(Array(buffer[..<markerIndex]), to: &pasteBuffer)
                }
                events.append(.paste(String(decoding: pasteBuffer, as: UTF8.self)))
            }
            buffer.removeFirst(markerIndex + Self.bracketedPasteEnd.count)
            self.pasteBuffer = nil
            discardingPaste = false
            return true
        }

        let retainedCount = longestSuffixPrefixLength(
            bytes: buffer,
            marker: Self.bracketedPasteEnd
        )
        let consumedCount = buffer.count - retainedCount
        if var pasteBuffer, !discardingPaste, consumedCount > 0 {
            appendPasteBytes(Array(buffer.prefix(consumedCount)), to: &pasteBuffer)
            self.pasteBuffer = pasteBuffer
        }
        buffer.removeFirst(consumedCount)
        return false
    }

    /// Appends paste bytes up to `maxPasteByteCount`, then switches to discard mode.
    private mutating func appendPasteBytes(_ bytes: [UInt8], to pasteBuffer: inout [UInt8]) {
        guard !bytes.isEmpty else { return }
        let room = maxPasteByteCount - pasteBuffer.count
        if room <= 0 {
            discardingPaste = true
            return
        }
        if bytes.count <= room {
            pasteBuffer.append(contentsOf: bytes)
            if pasteBuffer.count >= maxPasteByteCount {
                discardingPaste = true
            }
            return
        }
        pasteBuffer.append(contentsOf: bytes.prefix(room))
        discardingPaste = true
    }

    private func event(forCSI sequence: [UInt8]) -> TerminalEvent? {
        guard sequence.count >= 3 else { return nil }
        let final = sequence.last!
        let parameterBytes = sequence.dropFirst(2).dropLast()
        let parameters = String(decoding: parameterBytes, as: UTF8.self)

        let key: Key?
        switch final {
        case UInt8(ascii: "A"): key = .up
        case UInt8(ascii: "B"): key = .down
        case UInt8(ascii: "C"): key = .right
        case UInt8(ascii: "D"): key = .left
        case UInt8(ascii: "H"): key = .home
        case UInt8(ascii: "F"): key = .end
        case UInt8(ascii: "Z"):
            return .key(KeyEvent(key: .tab, modifiers: .shift))
        case UInt8(ascii: "~"): key = Int(parameters).flatMap { Self.tildeKeys[$0] }
        default: key = nil
        }

        return key.map { .key(KeyEvent(key: $0)) }
    }

    private func controlEvent(for byte: UInt8) -> TerminalEvent? {
        switch byte {
        case 3: return .key(KeyEvent(key: .char("c"), modifiers: .control))
        case 8, 127: return .key(KeyEvent(key: .backspace))
        case 9: return .key(KeyEvent(key: .tab))
        case 10, 13: return .key(KeyEvent(key: .enter))
        default: return nil
        }
    }
}

private enum ScalarDecodeResult {
    case complete(UnicodeScalar, length: Int)
    case incomplete
    case invalid
}

private func decodeScalar<C: Collection>(in bytes: C) -> ScalarDecodeResult
where C.Element == UInt8, C.Index == Int {
    guard let first = bytes.first else { return .incomplete }

    let length: Int
    switch first {
    case 0x00...0x7f: length = 1
    case 0xc2...0xdf: length = 2
    case 0xe0...0xef: length = 3
    case 0xf0...0xf4: length = 4
    default: return .invalid
    }

    let available = min(length, bytes.count)
    if available >= 2 {
        let second = bytes[bytes.index(bytes.startIndex, offsetBy: 1)]
        let validSecond: Bool
        switch first {
        case 0xe0: validSecond = (0xa0...0xbf).contains(second)
        case 0xed: validSecond = (0x80...0x9f).contains(second)
        case 0xf0: validSecond = (0x90...0xbf).contains(second)
        case 0xf4: validSecond = (0x80...0x8f).contains(second)
        default: validSecond = (0x80...0xbf).contains(second)
        }
        if !validSecond { return .invalid }
    }

    if available > 2 {
        for offset in 2..<available {
            let byte = bytes[bytes.index(bytes.startIndex, offsetBy: offset)]
            if !(0x80...0xbf).contains(byte) { return .invalid }
        }
    }

    guard bytes.count >= length else { return .incomplete }
    let prefix = Array(bytes.prefix(length))
    guard let scalar = String(bytes: prefix, encoding: .utf8)?.unicodeScalars.first else {
        return .invalid
    }
    return .complete(scalar, length: length)
}

private func longestSuffixPrefixLength(bytes: [UInt8], marker: [UInt8]) -> Int {
    let maximum = min(bytes.count, marker.count - 1)
    guard maximum > 0 else { return 0 }
    for length in stride(from: maximum, through: 1, by: -1) {
        if bytes.suffix(length).elementsEqual(marker.prefix(length)) { return length }
    }
    return 0
}

private extension Array where Element: Equatable {
    func firstRange(of needle: [Element]) -> Range<Int>? {
        guard !needle.isEmpty, count >= needle.count else { return nil }
        for start in 0...(count - needle.count) {
            let end = start + needle.count
            if self[start..<end].elementsEqual(needle) { return start..<end }
        }
        return nil
    }
}

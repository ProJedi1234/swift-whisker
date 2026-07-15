func terminalCellWidth(_ character: Character) -> Int {
    let scalars = character.unicodeScalars
    let hasEmojiPresentation = scalars.contains { $0.properties.isEmojiPresentation }
    let hasEmojiJoiner = scalars.contains { $0.value == 0x200d || $0.value == 0xfe0f }
    let hasWideScalar = scalars.contains { isWideTerminalScalar($0.value) }
    if hasEmojiPresentation || hasEmojiJoiner || hasWideScalar { return 2 }

    return scalars.reduce(into: 0) { width, scalar in
        switch scalar.properties.generalCategory {
        case .control, .format, .nonspacingMark, .enclosingMark, .spacingMark:
            break
        default:
            width += 1
        }
    }
}

func terminalTextWidth(
    _ text: some StringProtocol,
    replacingControlCharacters: Bool = false
) -> Int {
    text.reduce(into: 0) { width, character in
        let rendered = replacingControlCharacters
            ? terminalSafeCharacter(character)
            : character
        width += terminalCellWidth(rendered)
    }
}

func textInputCursorColumn(for node: Node) -> Int {
    let displayText = node[.displayText] ?? node[.getText]?() ?? ""
    let characterOffset = min(
        max(0, node[.cursorPosition] ?? displayText.count),
        displayText.count
    )
    if node[.isSecure] == true { return characterOffset }

    let store = node[.pasteStore] ?? [:]
    return PasteCollapse.visualWidth(
        displayText: displayText,
        store: store,
        upToCharacterOffset: characterOffset,
        replacingControlCharacters: true
    )
}

func terminalSafeCharacter(_ character: Character) -> Character {
    character.unicodeScalars.allSatisfy {
        $0.value >= 0x20 && $0.value != 0x7f
    } ? character : " "
}

private func isWideTerminalScalar(_ value: UInt32) -> Bool {
    switch value {
    case 0x1100...0x115f,
         0x2329...0x232a,
         0x2e80...0x303e,
         0x3040...0xa4cf,
         0xac00...0xd7a3,
         0xf900...0xfaff,
         0xfe10...0xfe19,
         0xfe30...0xfe6f,
         0xff00...0xff60,
         0xffe0...0xffe6,
         0x1f300...0x1faff,
         0x20000...0x3fffd:
        return true
    default:
        return false
    }
}

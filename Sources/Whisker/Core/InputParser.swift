struct InputParser {
    static func parse(_ bytes: [UInt8]) -> TerminalEvent? {
        guard !bytes.isEmpty else { return nil }

        if bytes.count == 1 {
            let byte = bytes[0]
            switch byte {
            case 3: return .key(KeyEvent(key: .char("c"), modifiers: .control))  // Ctrl+C
            case 9: return .key(KeyEvent(key: .tab))
            case 13: return .key(KeyEvent(key: .enter))
            case 27: return .key(KeyEvent(key: .escape))
            case 127: return .key(KeyEvent(key: .backspace))
            case 32...126:
                return .key(KeyEvent(key: .char(Character(UnicodeScalar(byte)))))
            default:
                return nil
            }
        }

        if bytes[0] == 27 && bytes.count >= 3 && bytes[1] == 91 {
            switch bytes[2] {
            case 65: return .key(KeyEvent(key: .up))
            case 66: return .key(KeyEvent(key: .down))
            case 67: return .key(KeyEvent(key: .right))
            case 68: return .key(KeyEvent(key: .left))
            case 72: return .key(KeyEvent(key: .home))
            case 70: return .key(KeyEvent(key: .end))
            case 90: return .key(KeyEvent(key: .tab, modifiers: .shift))
            default: break
            }
        }

        return nil
    }
}

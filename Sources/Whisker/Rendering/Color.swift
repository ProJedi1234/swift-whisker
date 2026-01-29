/// Terminal color representation
public enum Color: Equatable, Sendable {
    /// Default terminal color (foreground or background)
    case `default`

    /// Standard ANSI colors (0-7)
    case black, red, green, yellow, blue, magenta, cyan, white

    /// Bright ANSI colors (8-15)
    case brightBlack, brightRed, brightGreen, brightYellow
    case brightBlue, brightMagenta, brightCyan, brightWhite

    /// 256-color palette (0-255)
    case ansi256(UInt8)

    /// True color (24-bit RGB)
    case rgb(UInt8, UInt8, UInt8)

    // MARK: - Convenience initializers

    public static func hex(_ hex: UInt32) -> Color {
        let r = UInt8((hex >> 16) & 0xFF)
        let g = UInt8((hex >> 8) & 0xFF)
        let b = UInt8(hex & 0xFF)
        return .rgb(r, g, b)
    }

    // MARK: - Common colors

    public static let gray = Color.ansi256(244)
    public static let darkGray = Color.ansi256(238)
    public static let lightGray = Color.ansi256(250)

    public static let orange = Color.ansi256(208)
    public static let pink = Color.ansi256(213)
    public static let purple = Color.ansi256(129)
    public static let teal = Color.ansi256(30)
}

// MARK: - ANSI Escape Sequences

extension Color {
    /// ANSI escape sequence for foreground color
    var foregroundSequence: String {
        switch self {
        case .default: return "\u{1b}[39m"
        case .black: return "\u{1b}[30m"
        case .red: return "\u{1b}[31m"
        case .green: return "\u{1b}[32m"
        case .yellow: return "\u{1b}[33m"
        case .blue: return "\u{1b}[34m"
        case .magenta: return "\u{1b}[35m"
        case .cyan: return "\u{1b}[36m"
        case .white: return "\u{1b}[37m"
        case .brightBlack: return "\u{1b}[90m"
        case .brightRed: return "\u{1b}[91m"
        case .brightGreen: return "\u{1b}[92m"
        case .brightYellow: return "\u{1b}[93m"
        case .brightBlue: return "\u{1b}[94m"
        case .brightMagenta: return "\u{1b}[95m"
        case .brightCyan: return "\u{1b}[96m"
        case .brightWhite: return "\u{1b}[97m"
        case .ansi256(let code): return "\u{1b}[38;5;\(code)m"
        case .rgb(let r, let g, let b): return "\u{1b}[38;2;\(r);\(g);\(b)m"
        }
    }

    /// ANSI escape sequence for background color
    var backgroundSequence: String {
        switch self {
        case .default: return "\u{1b}[49m"
        case .black: return "\u{1b}[40m"
        case .red: return "\u{1b}[41m"
        case .green: return "\u{1b}[42m"
        case .yellow: return "\u{1b}[43m"
        case .blue: return "\u{1b}[44m"
        case .magenta: return "\u{1b}[45m"
        case .cyan: return "\u{1b}[46m"
        case .white: return "\u{1b}[47m"
        case .brightBlack: return "\u{1b}[100m"
        case .brightRed: return "\u{1b}[101m"
        case .brightGreen: return "\u{1b}[102m"
        case .brightYellow: return "\u{1b}[103m"
        case .brightBlue: return "\u{1b}[104m"
        case .brightMagenta: return "\u{1b}[105m"
        case .brightCyan: return "\u{1b}[106m"
        case .brightWhite: return "\u{1b}[107m"
        case .ansi256(let code): return "\u{1b}[48;5;\(code)m"
        case .rgb(let r, let g, let b): return "\u{1b}[48;2;\(r);\(g);\(b)m"
        }
    }
}

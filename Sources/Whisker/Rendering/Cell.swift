/// A single character cell in the terminal with styling
public struct Cell: Equatable, Sendable {
    public var char: Character
    public var style: Style

    public init(char: Character = " ", style: Style = .default) {
        self.char = char
        self.style = style
    }

    public static let empty = Cell(char: " ", style: .default)
}

/// Visual styling for a cell
public struct Style: Equatable, Sendable {
    public var foreground: Color
    public var background: Color
    public var attributes: Attributes

    public init(
        foreground: Color = .default,
        background: Color = .default,
        attributes: Attributes = []
    ) {
        self.foreground = foreground
        self.background = background
        self.attributes = attributes
    }

    public static let `default` = Style()

    // Convenience modifiers
    public func foreground(_ color: Color) -> Style {
        var copy = self
        copy.foreground = color
        return copy
    }

    public func background(_ color: Color) -> Style {
        var copy = self
        copy.background = color
        return copy
    }

    public func bold() -> Style {
        var copy = self
        copy.attributes.insert(.bold)
        return copy
    }

    public func italic() -> Style {
        var copy = self
        copy.attributes.insert(.italic)
        return copy
    }

    public func underline() -> Style {
        var copy = self
        copy.attributes.insert(.underline)
        return copy
    }
}

/// Text attributes (can be combined)
public struct Attributes: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let bold = Attributes(rawValue: 1 << 0)
    public static let italic = Attributes(rawValue: 1 << 1)
    public static let underline = Attributes(rawValue: 1 << 2)
    public static let strikethrough = Attributes(rawValue: 1 << 3)
    public static let dim = Attributes(rawValue: 1 << 4)
    public static let blink = Attributes(rawValue: 1 << 5)
    public static let reverse = Attributes(rawValue: 1 << 6)
}

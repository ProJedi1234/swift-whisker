/// A view that displays one or more lines of read-only text
public struct Text: View {
    public typealias Body = Never

    let content: String
    var style: Style

    public init(_ content: String) {
        self.content = content
        self.style = .default
    }

    public init(verbatim content: String) {
        self.content = content
        self.style = .default
    }

    public var body: Never {
        fatalError("Text has no body")
    }

    public func foregroundColor(_ color: Color) -> Text {
        var copy = self
        copy.style.foreground = color
        return copy
    }

    public func bold() -> Text {
        var copy = self
        copy.style.attributes.insert(.bold)
        return copy
    }

    public func italic() -> Text {
        var copy = self
        copy.style.attributes.insert(.italic)
        return copy
    }

    public func underline() -> Text {
        var copy = self
        copy.style.attributes.insert(.underline)
        return copy
    }

    public func strikethrough() -> Text {
        var copy = self
        copy.style.attributes.insert(.strikethrough)
        return copy
    }
}

extension Text {
    public static func + (lhs: Text, rhs: Text) -> Text {
        // For now, just concatenate content. A full implementation would
        // support AttributedString-like runs with different styles.
        Text(lhs.content + rhs.content)
    }
}

extension Text: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

extension Text: ExpressibleByStringInterpolation {
    public init(stringInterpolation: DefaultStringInterpolation) {
        self.init(stringInterpolation.description)
    }
}

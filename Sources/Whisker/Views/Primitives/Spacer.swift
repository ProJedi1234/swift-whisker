/// A flexible space that expands along the major axis of its containing stack
public struct Spacer: View {
    public typealias Body = Never

    let minLength: Int?

    public init(minLength: Int? = nil) {
        self.minLength = minLength
    }

    public var body: Never {
        fatalError("Spacer has no body")
    }
}

/// A visual divider line
public struct Divider: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("Divider has no body")
    }
}

/// Size proposal for layout
public struct ProposedSize {
    public var width: SizeConstraint
    public var height: SizeConstraint

    public init(width: SizeConstraint = .unconstrained, height: SizeConstraint = .unconstrained) {
        self.width = width
        self.height = height
    }

    public init(_ size: Size) {
        self.width = .exactly(size.width)
        self.height = .exactly(size.height)
    }

    public static let unspecified = ProposedSize()
}

/// A size constraint for one dimension
public enum SizeConstraint: Equatable {
    case exactly(Int)
    case atMost(Int)
    case unconstrained

    public var value: Int? {
        switch self {
        case .exactly(let v), .atMost(let v): return v
        case .unconstrained: return nil
        }
    }

    public func resolve(with preferred: Int) -> Int {
        switch self {
        case .exactly(let v): return v
        case .atMost(let v): return min(v, preferred)
        case .unconstrained: return preferred
        }
    }
}

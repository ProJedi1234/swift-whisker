/// A position in the terminal (column, line)
public struct Position: Equatable, Hashable, Sendable {
    public var x: Int  // column
    public var y: Int  // line/row

    public init(x: Int = 0, y: Int = 0) {
        self.x = x
        self.y = y
    }

    public static let zero = Position(x: 0, y: 0)

    public static func + (lhs: Position, rhs: Position) -> Position {
        Position(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: Position, rhs: Position) -> Position {
        Position(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}

/// A size in terminal cells
public struct Size: Equatable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int = 0, height: Int = 0) {
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public static let zero = Size(width: 0, height: 0)

    public var area: Int { width * height }
}

/// A rectangle in the terminal
public struct Rect: Equatable, Sendable {
    public var origin: Position
    public var size: Size

    public init(origin: Position = .zero, size: Size = .zero) {
        self.origin = origin
        self.size = size
    }

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.origin = Position(x: x, y: y)
        self.size = Size(width: width, height: height)
    }

    public static let zero = Rect()

    // Convenience accessors
    public var x: Int { origin.x }
    public var y: Int { origin.y }
    public var width: Int { size.width }
    public var height: Int { size.height }

    public var minX: Int { origin.x }
    public var maxX: Int { origin.x + size.width }
    public var minY: Int { origin.y }
    public var maxY: Int { origin.y + size.height }

    /// Check if a position is inside this rect
    public func contains(_ position: Position) -> Bool {
        position.x >= minX && position.x < maxX &&
            position.y >= minY && position.y < maxY
    }

    /// Return the intersection of two rects
    public func intersection(_ other: Rect) -> Rect? {
        let x1 = max(minX, other.minX)
        let y1 = max(minY, other.minY)
        let x2 = min(maxX, other.maxX)
        let y2 = min(maxY, other.maxY)

        if x1 < x2 && y1 < y2 {
            return Rect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
        }
        return nil
    }

    /// Return the union of two rects
    public func union(_ other: Rect) -> Rect {
        let x1 = min(minX, other.minX)
        let y1 = min(minY, other.minY)
        let x2 = max(maxX, other.maxX)
        let y2 = max(maxY, other.maxY)
        return Rect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }

    /// Inset the rect by the given amount on all sides
    public func inset(by amount: Int) -> Rect {
        Rect(
            x: origin.x + amount,
            y: origin.y + amount,
            width: max(0, size.width - amount * 2),
            height: max(0, size.height - amount * 2)
        )
    }

    /// Offset the rect by the given position
    public func offset(by delta: Position) -> Rect {
        Rect(origin: origin + delta, size: size)
    }
}

/// Insets/padding on each edge
public struct EdgeInsets: Equatable, Sendable {
    public var top: Int
    public var leading: Int
    public var bottom: Int
    public var trailing: Int

    public init(top: Int = 0, leading: Int = 0, bottom: Int = 0, trailing: Int = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public init(all: Int) {
        self.top = all
        self.leading = all
        self.bottom = all
        self.trailing = all
    }

    public init(horizontal: Int = 0, vertical: Int = 0) {
        self.top = vertical
        self.leading = horizontal
        self.bottom = vertical
        self.trailing = horizontal
    }

    public static let zero = EdgeInsets()

    public var horizontal: Int { leading + trailing }
    public var vertical: Int { top + bottom }
}

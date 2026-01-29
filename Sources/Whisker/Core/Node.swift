import Foundation

/// Runtime representation of a View in the tree.
/// Nodes persist across renders and store state.
public final class Node {
    // MARK: - Identity

    /// Unique identifier for this node
    let id: ObjectIdentifier

    /// Parent node (weak to avoid cycles)
    weak var parent: Node?

    /// Child nodes
    var children: [Node] = []

    // MARK: - View

    /// The view this node represents (type-erased)
    var viewType: Any.Type

    /// Closure to rebuild the view's body
    var buildBody: (() -> any View)?

    // MARK: - State

    /// Storage for @State values (keyed by property name)
    var stateStorage: [String: Any] = [:]

    /// Environment values inherited from parent
    var environment: EnvironmentValues = EnvironmentValues()

    // MARK: - Layout

    /// Computed frame after layout
    var frame: Rect = .zero

    /// Cached size from last layout pass
    var cachedSize: Size?

    // MARK: - Dirty Flags

    /// Whether this node needs its body rebuilt
    var needsRebuild: Bool = true

    /// Whether this node needs layout recalculated
    var needsLayout: Bool = true

    // MARK: - Focus

    /// Whether this node can receive focus
    var isFocusable: Bool = false

    /// Whether this node currently has focus
    var isFocused: Bool = false

    // MARK: - Rendering

    /// Primitive render function (for leaf nodes like Text)
    var render: ((Rect, inout RenderBuffer) -> Void)?

    /// Layout function (for containers)
    var layout: ((ProposedSize, [Node]) -> (Size, [(Node, Rect)]))?

    // MARK: - Initialization

    init(viewType: Any.Type) {
        self.id = ObjectIdentifier(Self.self)
        self.viewType = viewType
    }

    // MARK: - Tree Operations

    func addChild(_ child: Node) {
        child.parent = self
        children.append(child)
    }

    func removeAllChildren() {
        for child in children {
            child.parent = nil
        }
        children.removeAll()
    }

    /// Find the root node
    var root: Node {
        var node = self
        while let parent = node.parent {
            node = parent
        }
        return node
    }

    /// Depth-first traversal
    func traverse(_ visit: (Node) -> Void) {
        visit(self)
        for child in children {
            child.traverse(visit)
        }
    }

    /// Find first focusable node
    func findFirstFocusable() -> Node? {
        if isFocusable { return self }
        for child in children {
            if let found = child.findFirstFocusable() {
                return found
            }
        }
        return nil
    }

    /// Find next focusable node after this one
    func findNextFocusable() -> Node? {
        guard let parent = parent else { return nil }

        // Find our index in parent's children
        guard let index = parent.children.firstIndex(where: { $0 === self }) else {
            return nil
        }

        // Look in siblings after us
        for i in (index + 1)..<parent.children.count {
            if let found = parent.children[i].findFirstFocusable() {
                return found
            }
        }

        // Go up to parent and continue
        return parent.findNextFocusable()
    }

    /// Find previous focusable node before this one
    func findPreviousFocusable() -> Node? {
        guard let parent = parent else { return nil }

        guard let index = parent.children.firstIndex(where: { $0 === self }) else {
            return nil
        }

        // Look in siblings before us (in reverse)
        for i in (0..<index).reversed() {
            if let found = parent.children[i].findLastFocusable() {
                return found
            }
        }

        // Go up to parent
        if parent.isFocusable {
            return parent
        }
        return parent.findPreviousFocusable()
    }

    /// Find last focusable node in subtree
    func findLastFocusable() -> Node? {
        for child in children.reversed() {
            if let found = child.findLastFocusable() {
                return found
            }
        }
        if isFocusable { return self }
        return nil
    }
}

// MARK: - Environment

/// Container for environment values passed down the tree
public struct EnvironmentValues {
    var storage: [ObjectIdentifier: Any] = [:]

    public init() {}

    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get { storage[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
        set { storage[ObjectIdentifier(key)] = newValue }
    }
}

/// Protocol for environment keys
public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

// MARK: - Common Environment Keys

/// Foreground color environment key
public struct ForegroundColorKey: EnvironmentKey {
    public static var defaultValue: Color = .default
}

/// Background color environment key
public struct BackgroundColorKey: EnvironmentKey {
    public static var defaultValue: Color = .default
}

/// Bold text environment key
public struct BoldKey: EnvironmentKey {
    public static var defaultValue: Bool = false
}

extension EnvironmentValues {
    public var foregroundColor: Color {
        get { self[ForegroundColorKey.self] }
        set { self[ForegroundColorKey.self] = newValue }
    }

    public var backgroundColor: Color {
        get { self[BackgroundColorKey.self] }
        set { self[BackgroundColorKey.self] = newValue }
    }

    public var bold: Bool {
        get { self[BoldKey.self] }
        set { self[BoldKey.self] = newValue }
    }
}

// MARK: - Proposed Size

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

// MARK: - Render Buffer

/// Buffer that collects render commands
public struct RenderBuffer {
    public var commands: [RenderCommand] = []

    public init() {}

    public mutating func draw(_ char: Character, at position: Position, style: Style = .default) {
        commands.append(RenderCommand(
            position: position,
            cell: Cell(char: char, style: style)
        ))
    }

    public mutating func draw(_ string: String, at position: Position, style: Style = .default) {
        for (i, char) in string.enumerated() {
            draw(char, at: Position(x: position.x + i, y: position.y), style: style)
        }
    }

    public mutating func fill(_ rect: Rect, with char: Character = " ", style: Style = .default) {
        for y in rect.minY..<rect.maxY {
            for x in rect.minX..<rect.maxX {
                draw(char, at: Position(x: x, y: y), style: style)
            }
        }
    }
}

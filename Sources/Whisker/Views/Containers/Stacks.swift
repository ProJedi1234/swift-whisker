/// Internal protocol so NodeViewBuilder can detect any VStack<C> regardless of C
protocol _VStackProtocol {
    var _alignment: HorizontalAlignment { get }
    var _spacing: Int { get }
    var _content: Any { get }
}

/// Internal protocol so NodeViewBuilder can detect any HStack<C> regardless of C
protocol _HStackProtocol {
    var _alignment: VerticalAlignment { get }
    var _spacing: Int { get }
    var _content: Any { get }
}

/// Internal protocol so NodeViewBuilder can detect any ZStack<C> regardless of C
protocol _ZStackProtocol {
    var _alignment: Alignment { get }
    var _content: Any { get }
}

/// Alignment for items along the horizontal axis
public enum HorizontalAlignment: Sendable {
    case leading
    case center
    case trailing
}

/// Alignment for items along the vertical axis
public enum VerticalAlignment: Sendable {
    case top
    case center
    case bottom
}

/// Combined alignment for both axes
public struct Alignment: Sendable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment

    public init(horizontal: HorizontalAlignment = .center, vertical: VerticalAlignment = .center) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}

/// A view that arranges its children in a vertical line
public struct VStack<Content: View>: View, _VStackProtocol {
    var _alignment: HorizontalAlignment { alignment }
    var _spacing: Int { spacing }
    var _content: Any { content }
    public typealias Body = Never

    let alignment: HorizontalAlignment
    let spacing: Int
    let content: Content

    public init(
        alignment: HorizontalAlignment = .center,
        spacing: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: Never {
        fatalError("VStack has no body")
    }
}

/// A view that arranges its children in a horizontal line
public struct HStack<Content: View>: View, _HStackProtocol {
    var _alignment: VerticalAlignment { alignment }
    var _spacing: Int { spacing }
    var _content: Any { content }
    public typealias Body = Never

    let alignment: VerticalAlignment
    let spacing: Int
    let content: Content

    public init(
        alignment: VerticalAlignment = .center,
        spacing: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: Never {
        fatalError("HStack has no body")
    }
}

/// A view that overlays its children, aligning them in both axes
public struct ZStack<Content: View>: View, _ZStackProtocol {
    var _alignment: Alignment { alignment }
    var _content: Any { content }
    public typealias Body = Never

    let alignment: Alignment
    let content: Content

    public init(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.content = content()
    }

    public var body: Never {
        fatalError("ZStack has no body")
    }
}

/// A view that groups multiple views without affecting layout
public struct Group<Content: View>: View {
    public typealias Body = Content

    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: Content {
        content
    }
}

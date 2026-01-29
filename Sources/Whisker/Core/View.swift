/// The core View protocol - all UI components conform to this.
/// Mirrors SwiftUI's View protocol.
public protocol View {
    associatedtype Body: View

    @ViewBuilder
    var body: Body { get }
}

// MARK: - Never as View (for primitives)

extension Never: View {
    public typealias Body = Never

    public var body: Never {
        fatalError("Never has no body")
    }
}

// MARK: - ViewBuilder

@resultBuilder
public struct ViewBuilder {
    // Empty
    public static func buildBlock() -> EmptyView {
        EmptyView()
    }

    // Single view
    public static func buildBlock<V: View>(_ content: V) -> V {
        content
    }

    // Two views
    public static func buildBlock<V0: View, V1: View>(
        _ v0: V0, _ v1: V1
    ) -> TupleView<(V0, V1)> {
        TupleView((v0, v1))
    }

    // Three views
    public static func buildBlock<V0: View, V1: View, V2: View>(
        _ v0: V0, _ v1: V1, _ v2: V2
    ) -> TupleView<(V0, V1, V2)> {
        TupleView((v0, v1, v2))
    }

    // Four views
    public static func buildBlock<V0: View, V1: View, V2: View, V3: View>(
        _ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3
    ) -> TupleView<(V0, V1, V2, V3)> {
        TupleView((v0, v1, v2, v3))
    }

    // Five views
    public static func buildBlock<V0: View, V1: View, V2: View, V3: View, V4: View>(
        _ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4
    ) -> TupleView<(V0, V1, V2, V3, V4)> {
        TupleView((v0, v1, v2, v3, v4))
    }

    // Optionals
    public static func buildOptional<V: View>(_ component: V?) -> V? {
        component
    }

    // Conditionals
    public static func buildEither<TrueView: View, FalseView: View>(
        first component: TrueView
    ) -> ConditionalView<TrueView, FalseView> {
        .trueView(component)
    }

    public static func buildEither<TrueView: View, FalseView: View>(
        second component: FalseView
    ) -> ConditionalView<TrueView, FalseView> {
        .falseView(component)
    }
}

// MARK: - Supporting Types

/// Internal protocol so Application can unwrap any TupleView<T> regardless of T
protocol _TupleViewProtocol {
    var _tupleValue: Any { get }
}

/// Container for multiple views from ViewBuilder
public struct TupleView<T>: View, _TupleViewProtocol {
    var _tupleValue: Any { value }
    public typealias Body = Never

    public let value: T

    public init(_ value: T) {
        self.value = value
    }

    public var body: Never {
        fatalError("TupleView has no body")
    }
}

/// Represents an if/else in ViewBuilder
public enum ConditionalView<TrueView: View, FalseView: View>: View {
    case trueView(TrueView)
    case falseView(FalseView)

    public typealias Body = Never

    public var body: Never {
        fatalError("ConditionalView has no body")
    }
}

/// Optional view wrapper
extension Optional: View where Wrapped: View {
    public typealias Body = Never

    public var body: Never {
        fatalError("Optional<View> has no body")
    }
}

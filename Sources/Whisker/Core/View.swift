/// The core View protocol - all UI components conform to this.
/// Mirrors SwiftUI's View protocol.
public protocol View {
    associatedtype Body: View

    @ViewBuilder
    var body: Body { get }
}

extension Never: View {
    public typealias Body = Never

    public var body: Never {
        fatalError("Never has no body")
    }
}

@resultBuilder
public struct ViewBuilder {
    public static func buildBlock() -> EmptyView {
        EmptyView()
    }

    public static func buildBlock<V: View>(_ content: V) -> V {
        content
    }

    public static func buildBlock<V0: View, V1: View>(
        _ v0: V0, _ v1: V1
    ) -> TupleView<(V0, V1)> {
        TupleView((v0, v1))
    }

    // @resultBuilder type-erasure plumbing, not user-facing data
    // swiftlint:disable large_tuple
    public static func buildBlock<V0: View, V1: View, V2: View>(
        _ v0: V0, _ v1: V1, _ v2: V2
    ) -> TupleView<(V0, V1, V2)> {
        TupleView((v0, v1, v2))
    }

    public static func buildBlock<V0: View, V1: View, V2: View, V3: View>(
        _ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3
    ) -> TupleView<(V0, V1, V2, V3)> {
        TupleView((v0, v1, v2, v3))
    }

    public static func buildBlock<V0: View, V1: View, V2: View, V3: View, V4: View>(
        _ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4
    ) -> TupleView<(V0, V1, V2, V3, V4)> {
        TupleView((v0, v1, v2, v3, v4))
    }
    // swiftlint:enable large_tuple

    public static func buildBlock<V0: View, V1: View, V2: View, V3: View, V4: View, V5: View>(
        _ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4, _ v5: V5
    ) -> TupleView<(V0, V1, V2, V3, V4, V5)> {
        TupleView((v0, v1, v2, v3, v4, v5))
    }

    public static func buildBlock<V0: View, V1: View, V2: View, V3: View, V4: View, V5: View, V6: View>(
        _ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4, _ v5: V5, _ v6: V6
    ) -> TupleView<(V0, V1, V2, V3, V4, V5, V6)> {
        TupleView((v0, v1, v2, v3, v4, v5, v6))
    }

    public static func buildBlock<
        V0: View, V1: View, V2: View, V3: View, V4: View, V5: View, V6: View, V7: View
    >(
        _ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4, _ v5: V5, _ v6: V6, _ v7: V7
    ) -> TupleView<(V0, V1, V2, V3, V4, V5, V6, V7)> {
        TupleView((v0, v1, v2, v3, v4, v5, v6, v7))
    }

    public static func buildBlock<
        V0: View, V1: View, V2: View, V3: View, V4: View, V5: View, V6: View, V7: View, V8: View
    >(
        _ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4, _ v5: V5, _ v6: V6, _ v7: V7, _ v8: V8
    ) -> TupleView<(V0, V1, V2, V3, V4, V5, V6, V7, V8)> {
        TupleView((v0, v1, v2, v3, v4, v5, v6, v7, v8))
    }

    public static func buildBlock<
        V0: View, V1: View, V2: View, V3: View, V4: View, V5: View, V6: View, V7: View, V8: View, V9: View
    >(
        _ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4, _ v5: V5, _ v6: V6, _ v7: V7, _ v8: V8, _ v9: V9
    ) -> TupleView<(V0, V1, V2, V3, V4, V5, V6, V7, V8, V9)> {
        TupleView((v0, v1, v2, v3, v4, v5, v6, v7, v8, v9))
    }

    public static func buildOptional<V: View>(_ component: V?) -> V? {
        component
    }

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

/// Internal protocol so NodeViewBuilder can detect any ConditionalView regardless of generic parameters
protocol _ConditionalViewProtocol {
    var _activeView: any View { get }
}

/// Represents an if/else in ViewBuilder
public enum ConditionalView<TrueView: View, FalseView: View>: View, _ConditionalViewProtocol {
    var _activeView: any View {
        switch self {
        case .trueView(let view): return view
        case .falseView(let view): return view
        }
    }
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

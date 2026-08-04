// MARK: - Focusable Modifier

/// Internal protocol so NodeViewBuilder can detect any FocusableModifier regardless of Content type
protocol _FocusableModifierProtocol {
    var _content: any View { get }
    var _isFocusable: Bool { get }
}

/// A modifier that marks its view's node as focusable so it participates in
/// the focus ring alongside built-in controls.
struct FocusableModifier<Content: View>: View, _FocusableModifierProtocol {
    public typealias Body = Never

    let content: Content
    let isFocusable: Bool

    var _content: any View { content }
    var _isFocusable: Bool { isFocusable }

    public var body: Never {
        fatalError("FocusableModifier has no body")
    }
}

public extension View {
    /// Add this view to the focus ring so Tab and the arrow keys can move
    /// focus to it, like a built-in control.
    ///
    /// Combine with ``onKeyPress(_:)`` to receive key events while focused:
    ///
    ///     DetailPane()
    ///         .focusable()
    ///         .onKeyPress { event in
    ///             handle(event)
    ///         }
    func focusable(_ isFocusable: Bool = true) -> some View {
        FocusableModifier(content: self, isFocusable: isFocusable)
    }
}

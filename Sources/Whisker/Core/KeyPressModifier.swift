// MARK: - Key Press Modifier

/// Internal protocol so NodeViewBuilder can detect any KeyPressModifier regardless of Content type
protocol _KeyPressModifierProtocol {
    var _content: any View { get }
    var _handler: (KeyEvent) -> Bool { get }
}

/// A modifier that installs a key-event handler on its view's node.
/// When the wrapped view (or any focused descendant) is focused, key events are
/// offered to the handler before default handling such as focus traversal.
struct KeyPressModifier<Content: View>: View, _KeyPressModifierProtocol {
    public typealias Body = Never

    let content: Content
    let handler: (KeyEvent) -> Bool

    var _content: any View { content }
    var _handler: (KeyEvent) -> Bool { handler }

    public var body: Never {
        fatalError("KeyPressModifier has no body")
    }
}

public extension View {
    /// Handle key events delivered to this view while it (or a focused
    /// descendant) has focus.
    ///
    /// Return `true` from the handler to consume the key, or `false` to let
    /// default handling proceed — for `.tab`/`.up`/`.down` that means focus
    /// traversal; an unconsumed `.escape` is dropped.
    ///
    ///     DetailPane()
    ///         .focusable()
    ///         .onKeyPress { event in
    ///             if event.key == .enter {
    ///                 activate()
    ///                 return true
    ///             }
    ///             return false
    ///         }
    func onKeyPress(_ handler: @escaping (KeyEvent) -> Bool) -> some View {
        KeyPressModifier(content: self, handler: handler)
    }
}

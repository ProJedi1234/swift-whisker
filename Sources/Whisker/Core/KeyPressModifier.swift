// MARK: - Key Press Result

/// The result of a `.onKeyPress` handler, mirroring SwiftUI's `KeyPress.Result`.
public enum KeyPressResult: Sendable, Equatable {
    /// The handler consumed the key; no default handling occurs.
    case handled
    /// The handler ignored the key; default handling proceeds — for
    /// `.tab`/`.up`/`.down` that means focus traversal, and an unconsumed
    /// `.escape` is dropped.
    case ignored
}

// MARK: - Key Press Modifier

/// Internal protocol so NodeViewBuilder can detect any KeyPressModifier regardless of Content type
protocol _KeyPressModifierProtocol {
    var _content: any View { get }
    var _action: (KeyEvent) -> KeyPressResult { get }
}

/// A modifier that installs a key-event handler on its view's node.
/// When the wrapped view (or any focused descendant) is focused, key events are
/// offered to the handler before default handling such as focus traversal.
struct KeyPressModifier<Content: View>: View, _KeyPressModifierProtocol {
    public typealias Body = Never

    let content: Content
    let action: (KeyEvent) -> KeyPressResult

    var _content: any View { content }
    var _action: (KeyEvent) -> KeyPressResult { action }

    public var body: Never {
        fatalError("KeyPressModifier has no body")
    }
}

public extension View {
    /// Handle key events delivered to this view while it (or a focused
    /// descendant) has focus.
    ///
    /// Return `.handled` from the action to consume the key, or `.ignored` to
    /// let default handling proceed — for `.tab`/`.up`/`.down` that means focus
    /// traversal; an unconsumed `.escape` is dropped. Note that printable
    /// characters go to a focused text field's input handler first and never
    /// reach `.onKeyPress` while such a field has focus.
    ///
    /// Combine with ``focusable(_:)`` (in either order) so the view can
    /// receive focus in the first place:
    ///
    ///     DetailPane()
    ///         .focusable()
    ///         .onKeyPress { event in
    ///             if event.key == .enter {
    ///                 activate()
    ///                 return .handled
    ///             }
    ///             return .ignored
    ///         }
    func onKeyPress(action: @escaping (KeyEvent) -> KeyPressResult) -> some View {
        KeyPressModifier(content: self, action: action)
    }
}

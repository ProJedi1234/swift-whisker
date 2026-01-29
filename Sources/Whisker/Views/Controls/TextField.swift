/// A text input field with placeholder support
public struct TextField: View {
    public typealias Body = Never

    let placeholder: String
    let getText: () -> String
    let setText: (String) -> Void

    /// Create a text field with a binding
    public init(_ placeholder: String = "", text: Binding<String>) {
        self.placeholder = placeholder
        self.getText = { text.wrappedValue }
        self.setText = { text.wrappedValue = $0 }
    }

    /// Create a text field with getter/setter closures
    public init(_ placeholder: String = "", get: @escaping () -> String, set: @escaping (String) -> Void) {
        self.placeholder = placeholder
        self.getText = get
        self.setText = set
    }

    public var body: Never {
        fatalError("TextField has no body")
    }
}

/// A secure text field that masks input (for passwords)
public struct SecureField: View {
    public typealias Body = Never

    let placeholder: String
    let getText: () -> String
    let setText: (String) -> Void

    public init(_ placeholder: String = "", text: Binding<String>) {
        self.placeholder = placeholder
        self.getText = { text.wrappedValue }
        self.setText = { text.wrappedValue = $0 }
    }

    public var body: Never {
        fatalError("SecureField has no body")
    }
}

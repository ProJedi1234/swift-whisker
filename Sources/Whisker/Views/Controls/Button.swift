/// A clickable button with a label
public struct Button: View {
    public typealias Body = Never

    let label: String
    let action: () -> Void

    /// Create a button with a text label
    public init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    public var body: Never {
        fatalError("Button has no body")
    }
}

/// A toggle switch
public struct Toggle: View {
    public typealias Body = Never

    let label: String
    let isOn: Binding<Bool>

    public init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self.isOn = isOn
    }

    public var body: Never {
        fatalError("Toggle has no body")
    }
}

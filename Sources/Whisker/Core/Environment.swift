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

public struct ForegroundColorKey: EnvironmentKey {
    public static var defaultValue: Color = .default
}

public struct BackgroundColorKey: EnvironmentKey {
    public static var defaultValue: Color = .default
}

public struct BoldKey: EnvironmentKey {
    public static var defaultValue: Bool = false
}

public struct ItalicKey: EnvironmentKey {
    public static var defaultValue: Bool = false
}

public struct UnderlineKey: EnvironmentKey {
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

    public var italic: Bool {
        get { self[ItalicKey.self] }
        set { self[ItalicKey.self] = newValue }
    }

    public var underline: Bool {
        get { self[UnderlineKey.self] }
        set { self[UnderlineKey.self] = newValue }
    }
}

// MARK: - Environment Modifiers

protocol _EnvironmentModifierProtocol {
    var _content: any View { get }
    func _apply(to environment: inout EnvironmentValues)
}

struct EnvironmentModifier<Content: View, Value>: View, _EnvironmentModifierProtocol {
    public typealias Body = Never

    let content: Content
    let keyPath: WritableKeyPath<EnvironmentValues, Value>
    let value: Value

    var _content: any View { content }

    func _apply(to environment: inout EnvironmentValues) {
        environment[keyPath: keyPath] = value
    }

    public var body: Never {
        fatalError("EnvironmentModifier has no body")
    }
}

public extension View {
    func foregroundColor(_ color: Color) -> some View {
        EnvironmentModifier(content: self, keyPath: \.foregroundColor, value: color)
    }

    func backgroundColor(_ color: Color) -> some View {
        EnvironmentModifier(content: self, keyPath: \.backgroundColor, value: color)
    }

    func bold() -> some View {
        EnvironmentModifier(content: self, keyPath: \.bold, value: true)
    }

    func italic() -> some View {
        EnvironmentModifier(content: self, keyPath: \.italic, value: true)
    }

    func underline() -> some View {
        EnvironmentModifier(content: self, keyPath: \.underline, value: true)
    }
}

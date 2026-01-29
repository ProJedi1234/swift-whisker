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

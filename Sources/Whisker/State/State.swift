import Foundation

/// Context for the current node being built
public enum NodeContext {
    /// The node currently being built/rendered
    public static var current: Node?
}

/// Property wrapper for local view state
@propertyWrapper
public struct State<Value: Equatable>: DynamicProperty {
    private let key: String
    private let initialValue: Value

    public init(wrappedValue: Value, _ key: String = #function) {
        self.initialValue = wrappedValue
        self.key = key
    }

    public var wrappedValue: Value {
        get {
            guard let node = NodeContext.current else {
                return initialValue
            }
            return node.stateStorage[key] as? Value ?? initialValue
        }
        nonmutating set {
            guard let node = NodeContext.current else { return }
            let oldValue = node.stateStorage[key]
            node.stateStorage[key] = newValue

            // Only mark dirty if value actually changed
            if !isEqual(oldValue, newValue) {
                node.needsRebuild = true
                // Notify application to schedule update
                Application.shared?.scheduleUpdate()
            }
        }
    }

    public var projectedValue: Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0 }
        )
    }

    private func isEqual(_ lhs: Any?, _ rhs: Value) -> Bool {
        guard let lhs = lhs as? Value else { return false }
        return lhs == rhs
    }
}

/// Marker protocol for dynamic properties
public protocol DynamicProperty {}

/// Two-way binding to a value
@propertyWrapper
public struct Binding<Value> {
    private let getValue: () -> Value
    private let setValue: (Value) -> Void

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.getValue = get
        self.setValue = set
    }

    public var wrappedValue: Value {
        get { getValue() }
        nonmutating set { setValue(newValue) }
    }

    public var projectedValue: Binding<Value> {
        self
    }

    /// Create a constant binding (read-only)
    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }
}

// Extension to create bindings to optional values
extension Binding {
    public func map<T>(
        get: @escaping (Value) -> T,
        set: @escaping (T) -> Value
    ) -> Binding<T> {
        Binding<T>(
            get: { get(self.wrappedValue) },
            set: { self.wrappedValue = set($0) }
        )
    }
}

/// Property wrapper for environment values
@propertyWrapper
public struct Environment<Value>: DynamicProperty {
    private let keyPath: KeyPath<EnvironmentValues, Value>

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.keyPath = keyPath
    }

    public var wrappedValue: Value {
        let env = NodeContext.current?.environment ?? EnvironmentValues()
        return env[keyPath: keyPath]
    }
}

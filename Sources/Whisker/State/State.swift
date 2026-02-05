import Foundation

/// Context for the current node being built.
/// Thread-safety: NodeContext.current is only accessed from the main thread
/// during the synchronous rebuild pass in Application.runLoop(). No locking
/// is required because the entire build/layout/render pipeline is single-threaded.
public enum NodeContext {
    public static var current: Node?
}

/// Property wrapper for local view state.
/// Uses a class-based Box to capture the node reference on first access,
/// enabling wrappedValue and projectedValue to work in closures outside the build pass.
@propertyWrapper
public struct State<Value: Equatable>: DynamicProperty {
    private final class Box {
        weak var node: Node?
    }

    private let box = Box()
    private let key: String
    private let initialValue: Value

    public init(wrappedValue: Value, file: String = #fileID, line: Int = #line) {
        self.initialValue = wrappedValue
        self.key = "\(file):\(line)"
    }

    private var resolvedNode: Node? {
        let n = box.node ?? NodeContext.current
        if n != nil && box.node == nil { box.node = n }
        return n
    }

    public var wrappedValue: Value {
        get {
            guard let node = resolvedNode else { return initialValue }
            return node.persistentState[key] as? Value ?? initialValue
        }
        nonmutating set {
            guard let node = resolvedNode else { return }
            let oldValue = node.persistentState[key]
            node.persistentState[key] = newValue

            if !isEqual(oldValue, newValue) {
                node.needsRebuild = true
                Application.shared?.scheduleUpdate()
            }
        }
    }

    public var projectedValue: Binding<Value> {
        let box = self.box
        let key = self.key
        let initialValue = self.initialValue

        func resolveNode() -> Node? {
            let node = box.node ?? NodeContext.current
            if node != nil && box.node == nil { box.node = node }
            return node
        }

        return Binding(
            get: {
                guard let node = resolveNode() else { return initialValue }
                return node.persistentState[key] as? Value ?? initialValue
            },
            set: { newValue in
                guard let node = resolveNode() else { return }
                let oldValue = node.persistentState[key]
                node.persistentState[key] = newValue
                if !(oldValue as? Value == newValue) {
                    node.needsRebuild = true
                    Application.shared?.scheduleUpdate()
                }
            }
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

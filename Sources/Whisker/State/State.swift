import Foundation

/// Context for the current node being built.
/// Thread-safety: NodeContext.current is only accessed from the main thread
/// during the synchronous rebuild pass in Application.runLoop(). No locking
/// is required because the entire build/layout/render pipeline is single-threaded.
public enum NodeContext {
    public static var current: Node?
}

/// Property wrapper for local view state.
/// Uses a class-based Box to capture a strong reference to the node's
/// PersistentStateStorage on first access. Because PersistentStateStorage is
/// a reference type shared between old and new nodes during reconciliation,
/// async .task closures that captured @State can still write to the correct
/// storage even after the node tree has been rebuilt.
///
/// Thread safety: State mutations are protected by Application.stateLock so that
/// .task closures running on background threads can safely update @State.
@propertyWrapper
public struct State<Value: Equatable>: DynamicProperty {
    // @unchecked Sendable because access is synchronized via Application.stateLock
    private final class Box: @unchecked Sendable {
        /// Strong reference to the persistent state storage. Because this is a
        /// reference type, it remains valid and shared even after node reconciliation
        /// replaces the old node with a new one — both point to the same storage.
        var storage: PersistentStateStorage?

        /// Weak reference to the node, used only for setting needsRebuild.
        /// May become nil after reconciliation, but that's fine — the rebuild
        /// will be triggered via scheduleUpdate() regardless.
        weak var node: Node?
    }

    private let box = Box()
    private let key: String
    private let initialValue: Value

    public init(wrappedValue: Value, file: String = #fileID, line: Int = #line) {
        self.initialValue = wrappedValue
        self.key = "\(file):\(line)"
    }

    /// Eagerly bind the Box to the current node's storage during the build pass.
    public func _resolveStorage() {
        guard box.storage == nil, let node = NodeContext.current else { return }
        box.storage = node.persistentState
        box.node = node
    }

    /// Resolve the storage and node from the Box or current context.
    /// On first access during a build pass, captures both the storage and node.
    private var resolvedStorage: PersistentStateStorage? {
        if let storage = box.storage { return storage }
        guard let node = NodeContext.current else { return nil }
        box.storage = node.persistentState
        box.node = node
        return node.persistentState
    }

    public var wrappedValue: Value {
        get {
            let lock = Application.shared?.stateLock
            lock?.lock()
            defer { lock?.unlock() }
            guard let storage = resolvedStorage else { return initialValue }
            return storage[key] as? Value ?? initialValue
        }
        nonmutating set {
            let lock = Application.shared?.stateLock
            lock?.lock()
            guard let storage = resolvedStorage else {
                lock?.unlock()
                return
            }
            let oldValue = storage[key]
            storage[key] = newValue
            lock?.unlock()

            if !Self.isEqual(oldValue, newValue) {
                // needsRebuild on the node is best-effort — the node may have
                // been replaced by reconciliation, but scheduleUpdate() is the
                // authoritative trigger for the next rebuild pass.
                box.node?.needsRebuild = true
                Application.shared?.scheduleUpdate()
            }
        }
    }

    public var projectedValue: Binding<Value> {
        let box = self.box
        // Eagerly resolve during the build pass
        if box.storage == nil, let node = NodeContext.current {
            box.storage = node.persistentState
            box.node = node
        }
        let key = self.key
        let initialValue = self.initialValue

        func resolveStorage() -> PersistentStateStorage? {
            if let storage = box.storage { return storage }
            guard let node = NodeContext.current else { return nil }
            box.storage = node.persistentState
            box.node = node
            return node.persistentState
        }

        return Binding(
            get: {
                let lock = Application.shared?.stateLock
                lock?.lock()
                defer { lock?.unlock() }
                guard let storage = resolveStorage() else { return initialValue }
                return storage[key] as? Value ?? initialValue
            },
            set: { newValue in
                let lock = Application.shared?.stateLock
                lock?.lock()
                guard let storage = resolveStorage() else {
                    lock?.unlock()
                    return
                }
                let oldValue = storage[key]
                storage[key] = newValue
                lock?.unlock()

                if !Self.isEqual(oldValue, newValue) {
                    box.node?.needsRebuild = true
                    Application.shared?.scheduleUpdate()
                }
            }
        )
    }

    private static func isEqual(_ lhs: Any?, _ rhs: Value) -> Bool {
        guard let lhs = lhs as? Value else { return false }
        return lhs == rhs
    }
}

/// Marker protocol for dynamic properties.
/// Types conforming to this protocol can be eagerly resolved during the build
/// pass so that their internal storage references are captured while
/// NodeContext.current is available.
public protocol DynamicProperty {
    /// Called during the build pass to eagerly bind internal storage references
    /// to the current node context. The default implementation is a no-op.
    func _resolveStorage()
}

extension DynamicProperty {
    public func _resolveStorage() {}
}

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

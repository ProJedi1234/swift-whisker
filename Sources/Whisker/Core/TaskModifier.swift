import Foundation

// MARK: - Task Identity

/// Type-safe identity for `.task(id:)` that avoids string interpolation collisions.
/// Pairs the runtime type (via `ObjectIdentifier`) with the erased value (`AnyHashable`)
/// so that e.g. `Int(1)` and `String("1")` are never considered equal.
struct TaskIdentity: Equatable {
    /// Runtime type of the identity value, used to distinguish e.g. `Int(1)` from `String("1")`.
    let typeID: ObjectIdentifier
    /// Erased hashable identity value compared alongside `typeID`.
    let value: AnyHashable

    /// Create a task identity from a hashable value and its runtime type.
    init<H: Hashable>(_ id: H) {
        self.typeID = ObjectIdentifier(type(of: id))
        self.value = AnyHashable(id)
    }

    /// Sentinel identity used by the no-argument `.task {}` overload.
    private enum DefaultSentinel: Hashable { case `default` }
    static let `default` = TaskIdentity(DefaultSentinel.default)
}

// MARK: - Task Modifier

/// Internal protocol so NodeViewBuilder can detect any TaskModifier regardless of Content type
protocol _TaskModifierProtocol {
    var _content: any View { get }
    var _taskBody: @Sendable () async -> Void { get }
    var _taskID: TaskIdentity { get }
}

/// A modifier that spawns an async task when its view enters the tree.
/// The task is automatically cancelled when the view leaves the tree
/// (e.g. when a conditional branch switches).
struct TaskModifier<Content: View>: View, _TaskModifierProtocol {
    public typealias Body = Never

    let content: Content
    let taskBody: @Sendable () async -> Void
    let taskID: TaskIdentity

    var _content: any View { content }
    var _taskBody: @Sendable () async -> Void { taskBody }
    var _taskID: TaskIdentity { taskID }

    public var body: Never {
        fatalError("TaskModifier has no body")
    }
}

public extension View {
    /// Attach an asynchronous task that runs when this view appears.
    /// The task is cancelled when the view is removed from the tree.
    ///
    ///     Text("Loading...")
    ///         .task {
    ///             try? await Task.sleep(for: .seconds(2))
    ///             phase = 2
    ///         }
    func task(_ action: @escaping @Sendable () async -> Void) -> some View {
        TaskModifier(content: self, taskBody: action, taskID: .default)
    }

    /// Attach an asynchronous task that restarts when `id` changes.
    ///
    ///     Text("Count: \(n)")
    ///         .task(id: n) {
    ///             try? await Task.sleep(for: .seconds(1))
    ///             n += 1
    ///         }
    func task(id: some Hashable, _ action: @escaping @Sendable () async -> Void) -> some View {
        TaskModifier(content: self, taskBody: action, taskID: TaskIdentity(id))
    }
}

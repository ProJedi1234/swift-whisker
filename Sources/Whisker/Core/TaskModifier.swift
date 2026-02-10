import Foundation

// MARK: - Task Modifier

/// Internal protocol so NodeViewBuilder can detect any TaskModifier regardless of Content type
protocol _TaskModifierProtocol {
    var _content: any View { get }
    var _taskBody: @Sendable () async -> Void { get }
    var _taskID: String { get }
}

/// A modifier that spawns an async task when its view enters the tree.
/// The task is automatically cancelled when the view leaves the tree
/// (e.g. when a conditional branch switches).
struct TaskModifier<Content: View>: View, _TaskModifierProtocol {
    public typealias Body = Never

    let content: Content
    let taskBody: @Sendable () async -> Void
    let taskID: String

    var _content: any View { content }
    var _taskBody: @Sendable () async -> Void { taskBody }
    var _taskID: String { taskID }

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
        TaskModifier(content: self, taskBody: action, taskID: "default")
    }

    /// Attach an asynchronous task that restarts when `id` changes.
    ///
    ///     Text("Count: \(n)")
    ///         .task(id: n) {
    ///             try? await Task.sleep(for: .seconds(1))
    ///             n += 1
    ///         }
    func task(id: some Hashable, _ action: @escaping @Sendable () async -> Void) -> some View {
        TaskModifier(content: self, taskBody: action, taskID: "\(id)")
    }
}

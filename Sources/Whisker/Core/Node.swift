import Foundation

/// Reference-type wrapper for persistent state so that @State property wrappers
/// can hold a strong reference to the storage that survives node reconciliation.
/// When a new node is reconciled from an old node, both share the same storage
/// object, so async .task closures that captured the old node's storage still
/// write to the correct (shared) location.
public final class PersistentStateStorage: @unchecked Sendable {
    var values: [String: Any] = [:]

    subscript(key: String) -> Any? {
        get { values[key] }
        set { values[key] = newValue }
    }
}

public final class Node {
    weak var parent: Node?
    var children: [Node] = []
    var viewType: Any.Type
    var stateStorage: [String: Any] = [:]
    var persistentState = PersistentStateStorage()
    var conditionalBranch: Bool?
    var environment: EnvironmentValues = EnvironmentValues()
    var frame: Rect = .zero
    var needsRebuild: Bool = true
    var isFocusable: Bool = false
    var isFocused: Bool = false
    var render: ((Rect, inout RenderBuffer) -> Void)?
    var layout: ((ProposedSize, [Node]) -> (Size, [(Node, Rect)]))?

    /// Active async task spawned by a .task modifier. Stored as Any to avoid
    /// generic constraints on Node — cast to Task<Void, Never> for cancellation.
    var activeTask: Any?

    init(viewType: Any.Type) {
        self.viewType = viewType
    }

    /// Cancel any active async task on this node
    func cancelTask() {
        if let task = activeTask as? Task<Void, Never> {
            task.cancel()
        }
        activeTask = nil
    }

    /// Cancel all active async tasks in this subtree
    func cancelTasksRecursively() {
        cancelTask()
        for child in children {
            child.cancelTasksRecursively()
        }
    }

    func addChild(_ child: Node) {
        child.parent = self
        children.append(child)
    }

    func removeAllChildren() {
        for child in children {
            child.parent = nil
        }
        children.removeAll()
    }

    /// Find the root node
    var root: Node {
        var node = self
        while let parent = node.parent {
            node = parent
        }
        return node
    }

    /// Depth-first traversal
    func traverse(_ visit: (Node) -> Void) {
        visit(self)
        for child in children {
            child.traverse(visit)
        }
    }

    /// Find first focusable node
    func findFirstFocusable() -> Node? {
        if isFocusable { return self }
        for child in children {
            if let found = child.findFirstFocusable() {
                return found
            }
        }
        return nil
    }

    /// Find next focusable node after this one
    func findNextFocusable() -> Node? {
        guard let parent = parent else { return nil }

        // Find our index in parent's children
        guard let index = parent.children.firstIndex(where: { $0 === self }) else {
            return nil
        }

        // Look in siblings after us
        for i in (index + 1)..<parent.children.count {
            if let found = parent.children[i].findFirstFocusable() {
                return found
            }
        }

        // Go up to parent and continue
        return parent.findNextFocusable()
    }

    /// Find previous focusable node before this one
    func findPreviousFocusable() -> Node? {
        guard let parent = parent else { return nil }

        guard let index = parent.children.firstIndex(where: { $0 === self }) else {
            return nil
        }

        // Look in siblings before us (in reverse)
        for i in (0..<index).reversed() {
            if let found = parent.children[i].findLastFocusable() {
                return found
            }
        }

        // Go up to parent
        if parent.isFocusable {
            return parent
        }
        return parent.findPreviousFocusable()
    }

    /// Find last focusable node in subtree
    func findLastFocusable() -> Node? {
        for child in children.reversed() {
            if let found = child.findLastFocusable() {
                return found
            }
        }
        if isFocusable { return self }
        return nil
    }
}

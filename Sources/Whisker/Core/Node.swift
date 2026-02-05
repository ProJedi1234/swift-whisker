import Foundation

public final class Node {
    weak var parent: Node?
    var children: [Node] = []
    var viewType: Any.Type
    var stateStorage: [String: Any] = [:]
    var persistentState: [String: Any] = [:]
    var conditionalBranch: Bool? = nil
    var environment: EnvironmentValues = EnvironmentValues()
    var frame: Rect = .zero
    var needsRebuild: Bool = true
    var isFocusable: Bool = false
    var isFocused: Bool = false
    var render: ((Rect, inout RenderBuffer) -> Void)?
    var layout: ((ProposedSize, [Node]) -> (Size, [(Node, Rect)]))?

    init(viewType: Any.Type) {
        self.viewType = viewType
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

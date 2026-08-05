struct FocusManager {
    static func allFocusableNodes(root: Node?) -> [Node] {
        guard let root = root else { return [] }
        var result: [Node] = []
        root.traverse { node in
            if node.isFocusable {
                result.append(node)
            }
        }
        return result
    }

    static func restoreFocus(root: Node?, focusedIndex: inout Int, focusedNode: inout Node?) {
        let focusables = allFocusableNodes(root: root)
        guard !focusables.isEmpty else {
            focusedNode?.isFocused = false
            focusedNode = nil
            return
        }

        focusedNode?.isFocused = false // Clear focus on the previous node

        // Prefer re-binding to the same logical node. Reconciliation shares the
        // `persistentState` reference between an old node and its rebuilt
        // counterpart, so identity survives the rebuild even though the Node
        // objects are new. This keeps focus stable when other views enter or
        // leave the ring (e.g. a filtered list that empties out) — falling
        // back to the positional index only when the focused node itself left.
        if let previous = focusedNode,
           let index = focusables.firstIndex(where: { $0.persistentState === previous.persistentState }) {
            focusedIndex = index
        } else {
            focusedIndex = min(focusedIndex, focusables.count - 1)
        }
        focusedNode = focusables[focusedIndex]
        focusedNode?.isFocused = true
    }

    static func moveFocusNext(root: Node?, focusedIndex: inout Int, focusedNode: inout Node?) {
        let focusables = allFocusableNodes(root: root)
        guard !focusables.isEmpty else { return }

        focusedNode?.isFocused = false
        focusedIndex = (focusedIndex + 1) % focusables.count
        focusedNode = focusables[focusedIndex]
        focusedNode?.isFocused = true
    }

    static func moveFocusPrevious(root: Node?, focusedIndex: inout Int, focusedNode: inout Node?) {
        let focusables = allFocusableNodes(root: root)
        guard !focusables.isEmpty else { return }

        focusedNode?.isFocused = false
        focusedIndex = (focusedIndex - 1 + focusables.count) % focusables.count
        focusedNode = focusables[focusedIndex]
        focusedNode?.isFocused = true
    }
}

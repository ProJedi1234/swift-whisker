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
            focusedNode = nil
            return
        }

        focusedNode?.isFocused = false // Clear focus on the previous node
        focusedIndex = min(focusedIndex, focusables.count - 1)
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

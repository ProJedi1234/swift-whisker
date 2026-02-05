final class NodeViewBuilder {
    func buildNode(from view: any View, existing: Node? = nil) -> Node {
        let node = Node(viewType: type(of: view))

        let previousNode = NodeContext.current
        node.environment = previousNode?.environment ?? EnvironmentValues()
        NodeContext.current = node
        defer { NodeContext.current = previousNode }

        // Reconcile: copy persistent state from old node if types match
        if let existing = existing, existing.viewType == node.viewType {
            node.persistentState = existing.persistentState
        }

        if !buildPrimitiveNode(node, from: view) &&
            !buildContainerNode(node, from: view, existing: existing) &&
            !buildControlNode(node, from: view, existing: existing) {
            buildCompositeNode(node, view: view, existing: existing)
        }

        return node
    }

    // MARK: - Primitive Views

    private func buildPrimitiveNode(_ node: Node, from view: any View) -> Bool {
        if view is EmptyView {
            return true
        } else if let text = view as? Text {
            buildTextNode(node, text: text)
            return true
        } else if let spacer = view as? Spacer {
            buildSpacerNode(node, spacer: spacer)
            return true
        } else if view is Divider {
            buildDividerNode(node)
            return true
        }
        return false
    }

    private func buildTextNode(_ node: Node, text: Text) {
        node.render = { [weak node, text] frame, buffer in
            guard let node = node else { return }
            let style = text.style.resolved(with: node.environment)
            let content = text.content
            for (i, char) in content.prefix(frame.width).enumerated() {
                buffer.draw(char, at: Position(x: frame.x + i, y: frame.y), style: style)
            }
        }

        node.layout = { proposal, _ in
            let width = proposal.width.resolve(with: text.content.count)
            let height = proposal.height.resolve(with: 1)
            return (Size(width: width, height: height), [])
        }
    }

    private func buildSpacerNode(_ node: Node, spacer: Spacer) {
        let minLength = spacer.minLength ?? 0

        node.layout = { proposal, _ in
            let width = proposal.width.resolve(with: minLength)
            let height = proposal.height.resolve(with: minLength)
            return (Size(width: width, height: height), [])
        }
    }

    private func buildDividerNode(_ node: Node) {
        node.render = { [weak node] frame, buffer in
            guard let node = node else { return }
            let style = Style().resolved(
                with: node.environment,
                fallbackForeground: .brightBlack
            )
            for x in frame.x..<(frame.x + frame.width) {
                buffer.draw("─", at: Position(x: x, y: frame.y), style: style)
            }
        }

        node.layout = { proposal, _ in
            let width = proposal.width.resolve(with: 1)
            return (Size(width: width, height: 1), [])
        }
    }

    // MARK: - Container Views

    private func buildContainerNode(_ node: Node, from view: any View, existing: Node?) -> Bool {
        if let modifier = view as? any _EnvironmentModifierProtocol {
            buildEnvironmentNode(node, modifier: modifier, existing: existing)
            return true
        } else if let vstack = view as? any _VStackProtocol {
            buildVStackNode(node, content: vstack._content, alignment: vstack._alignment, spacing: vstack._spacing, existing: existing)
            return true
        } else if let hstack = view as? any _HStackProtocol {
            buildHStackNode(node, content: hstack._content, alignment: hstack._alignment, spacing: hstack._spacing, existing: existing)
            return true
        } else if let zstack = view as? any _ZStackProtocol {
            buildZStackNode(node, content: zstack._content, alignment: zstack._alignment, existing: existing)
            return true
        } else if let forEach = view as? any _ForEachProtocol {
            buildForEachNode(node, forEach: forEach, existing: existing)
            return true
        } else if let conditional = view as? any _ConditionalViewProtocol {
            buildConditionalNode(node, conditional: conditional, existing: existing)
            return true
        } else if let tupleView = view as? any _TupleViewProtocol {
            buildTupleViewNode(node, tupleView: tupleView, existing: existing)
            return true
        }
        return false
    }

    private func buildEnvironmentNode(_ node: Node, modifier: any _EnvironmentModifierProtocol, existing: Node?) {
        var environment = node.environment
        modifier._apply(to: &environment)
        node.environment = environment

        let existingChild = existing?.children.first
        let childNode = buildNode(from: modifier._content, existing: existingChild)
        node.addChild(childNode)
        node.layout = { [weak node] proposal, _ in
            guard let node = node, let firstChild = node.children.first else {
                return (.zero, [])
            }
            let childLayout = LayoutChild(node: firstChild)
            return (childLayout.sizeThatFits(proposal), [])
        }
    }

    func applyLayout(_ node: Node, engine: any Layout) {
        node[.placeChildren] = { [weak node] (bounds: Rect) in
            guard let node = node else { return }
            let children = node.children.map { LayoutChild(node: $0) }
            engine.placeChildren(in: bounds, children: children)
        }

        node.layout = { [weak node] proposal, _ in
            guard let node = node else { return (.zero, []) }
            let children = node.children.map { LayoutChild(node: $0) }
            return (engine.sizeThatFits(proposal: proposal, children: children), [])
        }
    }

    private func buildVStackNode(_ node: Node, content: Any, alignment: HorizontalAlignment, spacing: Int, existing: Node?) {
        let children = extractViews(from: content)
        let existingChildren = existing?.children ?? []
        for (index, childView) in children.enumerated() {
            let existingChild = index < existingChildren.count ? existingChildren[index] : nil
            node.addChild(buildNode(from: childView, existing: existingChild))
        }
        applyLayout(node, engine: VStackLayout(alignment: alignment, spacing: spacing))
    }

    private func buildHStackNode(_ node: Node, content: Any, alignment: VerticalAlignment, spacing: Int, existing: Node?) {
        let children = extractViews(from: content)
        let existingChildren = existing?.children ?? []
        for (index, childView) in children.enumerated() {
            let existingChild = index < existingChildren.count ? existingChildren[index] : nil
            node.addChild(buildNode(from: childView, existing: existingChild))
        }
        applyLayout(node, engine: HStackLayout(alignment: alignment, spacing: spacing))
    }

    private func buildZStackNode(_ node: Node, content: Any, alignment: Alignment, existing: Node?) {
        let children = extractViews(from: content)
        let existingChildren = existing?.children ?? []
        for (index, childView) in children.enumerated() {
            let existingChild = index < existingChildren.count ? existingChildren[index] : nil
            node.addChild(buildNode(from: childView, existing: existingChild))
        }
        applyLayout(node, engine: ZStackLayout(alignment: alignment))
    }

    private func buildForEachNode(_ node: Node, forEach: any _ForEachProtocol, existing: Node?) {
        let children = forEach._views
        let existingChildren = existing?.children ?? []

        // Reconciliation is currently positional for ForEach.
        // This assumes stable ordering (or append-only updates); reorders
        // and middle deletions may associate persistent state with new items.
        for (index, childView) in children.enumerated() {
            let existingChild = index < existingChildren.count ? existingChildren[index] : nil
            node.addChild(buildNode(from: childView, existing: existingChild))
        }
        applyLayout(node, engine: VStackLayout(alignment: .leading, spacing: 0))
    }

    private func buildConditionalNode(_ node: Node, conditional: any _ConditionalViewProtocol, existing: Node?) {
        let currentBranch = conditional._activeBranch
        node.conditionalBranch = currentBranch

        // Only pass existing child if branch matches
        let existingChild: Node?
        if let existing = existing,
           existing.conditionalBranch == currentBranch,
           let oldChild = existing.children.first {
            existingChild = oldChild
        } else {
            existingChild = nil
        }

        let childNode = buildNode(from: conditional._activeView, existing: existingChild)
        node.addChild(childNode)
        node.layout = { [weak node] proposal, _ in
            guard let node = node, let firstChild = node.children.first else {
                return (.zero, [])
            }
            let childLayout = LayoutChild(node: firstChild)
            return (childLayout.sizeThatFits(proposal), [])
        }
    }

    private func buildTupleViewNode(_ node: Node, tupleView: any _TupleViewProtocol, existing: Node?) {
        let children = extractViews(from: tupleView._tupleValue)
        let existingChildren = existing?.children ?? []
        for (index, childView) in children.enumerated() {
            let existingChild = index < existingChildren.count ? existingChildren[index] : nil
            node.addChild(buildNode(from: childView, existing: existingChild))
        }
        applyLayout(node, engine: VStackLayout(alignment: .leading, spacing: 0))
    }

    // MARK: - Composite Views (fallback)

    private func buildCompositeNode(_ node: Node, view: any View, existing: Node?) {
        func buildBody<V: View>(_ v: V) {
            guard V.Body.self != Never.self else { return }
            let body = v.body
            let existingChild = existing?.children.first
            let childNode = buildNode(from: body, existing: existingChild)
            node.addChild(childNode)
        }
        buildBody(view)

        node.layout = { [weak node] proposal, _ in
            guard let node = node, let firstChild = node.children.first else {
                return (.zero, [])
            }
            let childLayout = LayoutChild(node: firstChild)
            return (childLayout.sizeThatFits(proposal), [])
        }
    }

    // MARK: - Helpers

    func extractViews(from value: Any) -> [any View] {
        if let tupleView = value as? any _TupleViewProtocol {
            return extractViews(from: tupleView._tupleValue)
        }

        var views: [any View] = []
        let mirror = Mirror(reflecting: value)

        for child in mirror.children {
            if let view = child.value as? any View {
                views.append(view)
            }
        }

        if views.isEmpty {
            if let view = value as? any View {
                views.append(view)
            }
        }

        return views
    }
}

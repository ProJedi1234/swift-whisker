import Foundation

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
        } else if let existing = existing {
            // View type changed — cancel any async tasks in the old subtree
            existing.cancelTasksRecursively()
        }

        // Eagerly resolve all @State properties so their Boxes capture the
        // current node's PersistentStateStorage. This is necessary for .task
        // closures that capture @State but don't read it during the build pass.
        resolveStateProperties(of: view)

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
        } else if let indicator = view as? ActivityIndicator {
            buildActivityIndicatorNode(node, indicator: indicator)
            return true
        }
        return false
    }

    private func buildTextNode(_ node: Node, text: Text) {
        node.render = { [weak node, text] frame, buffer in
            guard let node = node else { return }
            let style = text.style.resolved(with: node.environment)
            buffer.drawClipped(
                text.content,
                at: frame.origin,
                maxWidth: frame.width,
                style: style
            )
        }

        node.layout = { proposal, _ in
            let width = proposal.width.resolve(with: terminalTextWidth(text.content))
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
            let width: Int
            switch proposal.width {
            case .atMost(let v), .exactly(let v): width = v
            case .unconstrained: width = 1
            }
            return (Size(width: width, height: 1), [])
        }
    }

    /// Build a 1×1 animated spinner node and register it with the application run loop.
    private func buildActivityIndicatorNode(_ node: Node, indicator: ActivityIndicator) {
        Application.shared?.animationTickCount += 1

        node.render = { [weak node] frame, buffer in
            guard let node = node else { return }
            guard frame.width > 0, frame.height > 0 else { return }
            let style = Style().resolved(with: node.environment)
            let frameIndex = indicator.currentFrameIndex()
            let char = ActivityIndicator.frames[frameIndex]
            buffer.draw(char, at: Position(x: frame.x, y: frame.y), style: style)
        }

        node.layout = { proposal, _ in
            let width = proposal.width.resolve(with: 1)
            let height = proposal.height.resolve(with: 1)
            return (Size(width: width, height: height), [])
        }
    }

    // MARK: - Container Views

    private func buildContainerNode(_ node: Node, from view: any View, existing: Node?) -> Bool {
        if let modifier = view as? any _EnvironmentModifierProtocol {
            buildEnvironmentNode(node, modifier: modifier, existing: existing)
            return true
        } else if let taskMod = view as? any _TaskModifierProtocol {
            buildTaskModifierNode(node, modifier: taskMod, existing: existing)
            return true
        } else if let keyPress = view as? any _KeyPressModifierProtocol {
            buildKeyPressModifierNode(node, modifier: keyPress, existing: existing)
            return true
        } else if let focusable = view as? any _FocusableModifierProtocol {
            buildFocusableModifierNode(node, modifier: focusable, existing: existing)
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

    /// Build a passthrough node that spawns or preserves an async `.task` for its content.
    private func buildTaskModifierNode(_ node: Node, modifier: any _TaskModifierProtocol, existing: Node?) {
        // Build child content (pass through, same as EnvironmentModifier)
        let existingChild = existing?.children.first
        let childNode = buildNode(from: modifier._content, existing: existingChild)
        node.addChild(childNode)

        // Passthrough layout — the modifier is invisible, child determines size
        node.layout = { [weak node] proposal, _ in
            guard let node = node, let firstChild = node.children.first else {
                return (.zero, [])
            }
            let childLayout = LayoutChild(node: firstChild)
            return (childLayout.sizeThatFits(proposal), [])
        }

        // Task lifecycle: start a new task if this is a fresh appearance,
        // or if the task ID changed (for .task(id:) variant).
        // Use two keys: one for the task ID, one to track whether the task
        // has already been started (so we don't re-spawn after it completes).
        let taskIDKey = "_task_id"
        let taskStartedKey = "_task_started"
        let currentID = modifier._taskID
        let previousID = existing?.persistentState[taskIDKey] as? TaskIdentity
        let wasStarted = existing?.persistentState[taskStartedKey] as? Bool ?? false

        if previousID == currentID && wasStarted {
            // Same ID, task already started — carry forward (may still be running or finished)
            node.activeTask = existing?.activeTask
        } else {
            // New appearance or ID changed — cancel old task if any, start new one
            existing?.cancelTask()

            let taskBody = modifier._taskBody
            node.activeTask = Task {
                await taskBody()
            }
        }

        node.persistentState[taskIDKey] = currentID
        node.persistentState[taskStartedKey] = true
    }

    /// Build a passthrough node that offers key events to a `.onKeyPress` handler.
    /// Key events bubble from the focused node up through its ancestors, so the
    /// handler fires when the wrapped view (e.g. one marked `.focusable()`) or
    /// any focusable descendant has focus.
    private func buildKeyPressModifierNode(
        _ node: Node,
        modifier: any _KeyPressModifierProtocol,
        existing: Node?
    ) {
        let action = modifier._action
        node[.keyHandler] = { action($0) == .handled }
        buildPassthroughChild(node, content: modifier._content, existing: existing)
    }

    /// Build a passthrough node that adjusts its content's focus-ring membership.
    ///
    /// Focusability is stamped on the *content's* node rather than this wrapper:
    /// - Key dispatch bubbles upward from the focused node, so with focus on the
    ///   content every `.onKeyPress` wrapper fires whether it was applied before
    ///   or after `.focusable()` — the modifiers compose in either order.
    /// - Wrapping an inherently focusable control (e.g. `Button`) doesn't create
    ///   a second, duplicate focus stop, and `.focusable(false)` actually removes
    ///   the wrapped view from the focus ring.
    private func buildFocusableModifierNode(
        _ node: Node,
        modifier: any _FocusableModifierProtocol,
        existing: Node?
    ) {
        buildPassthroughChild(node, content: modifier._content, existing: existing)
        node.children.first?.isFocusable = modifier._isFocusable
    }

    /// Shared plumbing for invisible wrapper nodes: build the single child and
    /// adopt its size (same shape as EnvironmentModifier/TaskModifier layout).
    private func buildPassthroughChild(_ node: Node, content: any View, existing: Node?) {
        let existingChild = existing?.children.first
        let childNode = buildNode(from: content, existing: existingChild)
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
        cancelDroppedChildren(existingChildren, keeping: children.count)
        applyLayout(node, engine: VStackLayout(alignment: alignment, spacing: spacing))
    }

    private func buildHStackNode(_ node: Node, content: Any, alignment: VerticalAlignment, spacing: Int, existing: Node?) {
        let children = extractViews(from: content)
        let existingChildren = existing?.children ?? []
        for (index, childView) in children.enumerated() {
            let existingChild = index < existingChildren.count ? existingChildren[index] : nil
            node.addChild(buildNode(from: childView, existing: existingChild))
        }
        cancelDroppedChildren(existingChildren, keeping: children.count)
        applyLayout(node, engine: HStackLayout(alignment: alignment, spacing: spacing))
    }

    private func buildZStackNode(_ node: Node, content: Any, alignment: Alignment, existing: Node?) {
        let children = extractViews(from: content)
        let existingChildren = existing?.children ?? []
        for (index, childView) in children.enumerated() {
            let existingChild = index < existingChildren.count ? existingChildren[index] : nil
            node.addChild(buildNode(from: childView, existing: existingChild))
        }
        cancelDroppedChildren(existingChildren, keeping: children.count)
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
        cancelDroppedChildren(existingChildren, keeping: children.count)
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
            // Branch changed — cancel any async tasks in the old subtree
            existing?.children.first?.cancelTasksRecursively()
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
        cancelDroppedChildren(existingChildren, keeping: children.count)
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

    // MARK: - State Resolution

    /// Walk the view struct using Mirror and call _resolveStorage() on every
    /// @State (DynamicProperty) found. This ensures each @State's Box captures
    /// the current node's PersistentStateStorage while NodeContext.current is set.
    /// Without this, @State properties that are only used inside .task closures
    /// (and never read during body evaluation) would fail to resolve.
    private func resolveStateProperties(of view: any View) {
        let mirror = Mirror(reflecting: view)
        for child in mirror.children {
            if let prop = child.value as? any DynamicProperty {
                prop._resolveStorage()
            }
        }
    }

    // MARK: - Helpers

    /// Cancel async work in reconciled-out container children that are no longer in the tree.
    private func cancelDroppedChildren(_ existingChildren: [Node], keeping count: Int) {
        for dropped in existingChildren.dropFirst(count) {
            dropped.cancelTasksRecursively()
        }
    }

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

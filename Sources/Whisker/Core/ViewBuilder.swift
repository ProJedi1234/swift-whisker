final class NodeViewBuilder {
    func buildNode(from view: any View) -> Node {
        let node = Node(viewType: type(of: view))

        let previousNode = NodeContext.current
        NodeContext.current = node
        defer { NodeContext.current = previousNode }

        if view is EmptyView {
            return node
        } else if let text = view as? Text {
            buildTextNode(node, text: text)
        } else if let vstack = view as? any _VStackProtocol {
            buildVStackNode(node, content: vstack._content, alignment: vstack._alignment, spacing: vstack._spacing)
        } else if let hstack = view as? any _HStackProtocol {
            buildHStackNode(node, content: hstack._content, alignment: hstack._alignment, spacing: hstack._spacing)
        } else if let zstack = view as? any _ZStackProtocol {
            buildZStackNode(node, content: zstack._content, alignment: zstack._alignment)
        } else if view is Spacer {
            buildSpacerNode(node, spacer: view as! Spacer)
        } else if view is Divider {
            buildDividerNode(node)
        } else if let textField = view as? TextField {
            buildTextFieldNode(node, textField: textField)
        } else if let secureField = view as? SecureField {
            buildSecureFieldNode(node, secureField: secureField)
        } else if let button = view as? Button {
            buildButtonNode(node, button: button)
        } else if let toggle = view as? Toggle {
            buildToggleNode(node, toggle: toggle)
        } else if let forEach = view as? any _ForEachProtocol {
            let children = forEach._views
            for childView in children {
                node.addChild(buildNode(from: childView))
            }
            applyLayout(node, engine: VStackLayout(alignment: .leading, spacing: 0))
        } else if let conditional = view as? any _ConditionalViewProtocol {
            let childNode = buildNode(from: conditional._activeView)
            node.addChild(childNode)
            node.layout = { [weak node] proposal, _ in
                guard let node = node, let firstChild = node.children.first else {
                    return (.zero, [])
                }
                let childLayout = LayoutChild(node: firstChild)
                return (childLayout.sizeThatFits(proposal), [])
            }
        } else if let tupleView = view as? any _TupleViewProtocol {
            let children = extractViews(from: tupleView._tupleValue)
            for childView in children {
                node.addChild(buildNode(from: childView))
            }
            applyLayout(node, engine: VStackLayout(alignment: .leading, spacing: 0))
        } else {
            buildCompositeNode(node, view: view)
        }

        return node
    }

    private func buildTextNode(_ node: Node, text: Text) {
        node.render = { [text] frame, buffer in
            let style = text.style
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

    private func applyLayout(_ node: Node, engine: any Layout) {
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

    private func buildVStackNode(_ node: Node, content: Any, alignment: HorizontalAlignment, spacing: Int) {
        let children = extractViews(from: content)
        for childView in children {
            node.addChild(buildNode(from: childView))
        }
        applyLayout(node, engine: VStackLayout(alignment: alignment, spacing: spacing))
    }

    private func buildHStackNode(_ node: Node, content: Any, alignment: VerticalAlignment, spacing: Int) {
        let children = extractViews(from: content)
        for childView in children {
            node.addChild(buildNode(from: childView))
        }
        applyLayout(node, engine: HStackLayout(alignment: alignment, spacing: spacing))
    }

    private func buildZStackNode(_ node: Node, content: Any, alignment: Alignment) {
        let children = extractViews(from: content)
        for childView in children {
            node.addChild(buildNode(from: childView))
        }
        applyLayout(node, engine: ZStackLayout(alignment: alignment))
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
        node.render = { frame, buffer in
            let style = Style(foreground: .brightBlack)
            for x in frame.x..<(frame.x + frame.width) {
                buffer.draw("─", at: Position(x: x, y: frame.y), style: style)
            }
        }

        node.layout = { proposal, _ in
            let width = proposal.width.resolve(with: 1)
            return (Size(width: width, height: 1), [])
        }
    }

    private func buildToggleNode(_ node: Node, toggle: Toggle) {
        node.isFocusable = true

        node[.keyHandler] = { (event: KeyEvent) in
            if event.key == .enter || event.key == .char(" ") {
                toggle.isOn.wrappedValue.toggle()
                Application.shared?.scheduleUpdate()
            }
        }

        node.render = { [weak node] frame, buffer in
            guard let node = node else { return }
            let isOn = toggle.isOn.wrappedValue
            let indicator = isOn ? "[x]" : "[ ]"
            let text = "\(indicator) \(toggle.label)"

            let style: Style = node.isFocused
                ? Style(foreground: .black, background: .white, attributes: [.bold])
                : .default

            for (i, char) in text.prefix(frame.width).enumerated() {
                buffer.draw(char, at: Position(x: frame.x + i, y: frame.y), style: style)
            }
        }

        node.layout = { proposal, _ in
            let width = proposal.width.resolve(with: toggle.label.count + 4) // "[x] label"
            return (Size(width: width, height: 1), [])
        }
    }

    func buildInputFieldNode(
        _ node: Node,
        getText: @escaping () -> String,
        setText: @escaping (String) -> Void,
        placeholder: String,
        isSecure: Bool
    ) {
        node.isFocusable = true
        node[.getText] = getText
        node[.setText] = setText
        node[.placeholder] = placeholder
        node[.cursorPosition] = getText().count
        node[.isSecure] = isSecure

        let secureFieldWidth = 20

        node[.keyHandler] = { [weak node] (event: KeyEvent) in
            guard let node = node else { return }
            guard let getText = node[.getText],
                  let setText = node[.setText] else { return }

            var text = getText()
            var cursor = node[.cursorPosition] ?? text.count

            switch event.key {
            case .char(let c):
                let index = text.index(text.startIndex, offsetBy: min(cursor, text.count))
                text.insert(c, at: index)
                cursor += 1
            case .backspace:
                if cursor > 0 && !text.isEmpty {
                    let index = text.index(text.startIndex, offsetBy: cursor - 1)
                    text.remove(at: index)
                    cursor -= 1
                }
            case .delete:
                if cursor < text.count {
                    let index = text.index(text.startIndex, offsetBy: cursor)
                    text.remove(at: index)
                }
            case .left:
                cursor = max(0, cursor - 1)
            case .right:
                cursor = min(text.count, cursor + 1)
            case .home:
                cursor = 0
            case .end:
                cursor = text.count
            default:
                break
            }

            setText(text)
            node[.cursorPosition] = cursor
            Application.shared?.scheduleUpdate()
        }

        node.render = { [weak node] frame, buffer in
            guard let node = node else { return }
            let text = node[.getText]?() ?? ""
            let placeholder = node[.placeholder] ?? ""
            let displayText: String

            if text.isEmpty {
                displayText = placeholder
            } else if isSecure {
                displayText = String(repeating: "\u{2022}", count: text.count)
            } else {
                displayText = text
            }

            let style: Style = text.isEmpty
                ? Style(foreground: .brightBlack)
                : .default

            for (i, char) in displayText.prefix(frame.width).enumerated() {
                buffer.draw(char, at: Position(x: frame.x + i, y: frame.y), style: style)
            }
        }

        node.layout = { [weak node] proposal, _ in
            guard let node = node else { return (.zero, []) }
            let text = node[.getText]?() ?? ""
            let placeholder = node[.placeholder] ?? ""
            let displayText = text.isEmpty ? placeholder : text
            let displayWidth = isSecure ? secureFieldWidth : displayText.count
            let width = proposal.width.resolve(with: displayWidth)
            return (Size(width: width, height: 1), [])
        }
    }

    private func buildTextFieldNode(_ node: Node, textField: TextField) {
        buildInputFieldNode(
            node,
            getText: textField.getText,
            setText: textField.setText,
            placeholder: textField.placeholder,
            isSecure: false
        )
    }

    private func buildSecureFieldNode(_ node: Node, secureField: SecureField) {
        buildInputFieldNode(
            node,
            getText: secureField.getText,
            setText: secureField.setText,
            placeholder: secureField.placeholder,
            isSecure: true
        )
    }

    private func buildButtonNode(_ node: Node, button: Button) {
        node.isFocusable = true
        node[.action] = button.action
        node[.label] = button.label

        node[.keyHandler] = { [weak node] (event: KeyEvent) in
            guard let node = node else { return }
            if event.key == .enter || event.key == .char(" ") {
                if let action = node[.action] {
                    action()
                }
            }
        }

        node.render = { [weak node] frame, buffer in
            guard let node = node else { return }
            let label = node[.label] ?? "Button"

            let style: Style = node.isFocused
                ? Style(foreground: .black, background: .white, attributes: [.bold])
                : Style(foreground: .white)

            let text = "[ \(label) ]"
            for (i, char) in text.prefix(frame.width).enumerated() {
                buffer.draw(char, at: Position(x: frame.x + i, y: frame.y), style: style)
            }
        }

        node.layout = { proposal, _ in
            let label = button.label
            let width = proposal.width.resolve(with: label.count + 4) // "[ label ]"
            return (Size(width: width, height: 1), [])
        }
    }

    private func buildCompositeNode(_ node: Node, view: any View) {
        let mirror = Mirror(reflecting: view)

        if let value = mirror.children.first?.value {
            if let tupleView = value as? any View {
                let childNode = buildNode(from: tupleView)
                node.addChild(childNode)
            } else {
                let views = extractViews(from: value)
                for childView in views {
                    let childNode = buildNode(from: childView)
                    node.addChild(childNode)
                }
            }
        }

        node.layout = { [weak node] proposal, _ in
            guard let node = node, let firstChild = node.children.first else {
                return (.zero, [])
            }
            let childLayout = LayoutChild(node: firstChild)
            let size = childLayout.sizeThatFits(proposal)
            return (size, [])
        }
    }

    private func extractViews(from value: Any) -> [any View] {
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

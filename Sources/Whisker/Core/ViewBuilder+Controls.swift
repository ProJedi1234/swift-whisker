// MARK: - Control Views (TextField, SecureField, Button, Toggle)

extension NodeViewBuilder {
    func buildControlNode(_ node: Node, from view: any View) -> Bool {
        if let textField = view as? TextField {
            buildTextFieldNode(node, textField: textField)
            return true
        } else if let secureField = view as? SecureField {
            buildSecureFieldNode(node, secureField: secureField)
            return true
        } else if let button = view as? Button {
            buildButtonNode(node, button: button)
            return true
        } else if let toggle = view as? Toggle {
            buildToggleNode(node, toggle: toggle)
            return true
        }
        return false
    }

    // MARK: - Input Fields

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

        node[.keyHandler] = makeInputFieldKeyHandler(for: node)
        node.render = makeInputFieldRenderClosure(for: node, isSecure: isSecure)

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

    private func makeInputFieldKeyHandler(for node: Node) -> (KeyEvent) -> Void {
        return { [weak node] (event: KeyEvent) in
            guard let node = node else { return }
            guard let getText = node[.getText],
                  let setText = node[.setText] else { return }

            var text = getText()
            var cursor = node[.cursorPosition] ?? text.count
            NodeViewBuilder.applyKeyEdit(event.key, text: &text, cursor: &cursor)

            setText(text)
            node[.cursorPosition] = cursor
            Application.shared?.scheduleUpdate()
        }
    }

    private static func applyKeyEdit(_ key: Key, text: inout String, cursor: inout Int) {
        cursor = min(max(0, cursor), text.count)

        switch key {
        case .char(let c):
            let index = text.index(text.startIndex, offsetBy: cursor)
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
    }

    private func makeInputFieldRenderClosure(for node: Node, isSecure: Bool) -> (Rect, inout RenderBuffer) -> Void {
        return { [weak node] frame, buffer in
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

    // MARK: - Button

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

    // MARK: - Toggle

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
}

// MARK: - Control Views (TextField, SecureField, Button, Toggle)

extension NodeViewBuilder {
    func buildControlNode(_ node: Node, from view: any View, existing: Node?) -> Bool {
        if let textField = view as? TextField {
            buildTextFieldNode(node, textField: textField, existing: existing)
            return true
        } else if let secureField = view as? SecureField {
            buildSecureFieldNode(node, secureField: secureField, existing: existing)
            return true
        } else if let button = view as? Button {
            buildButtonNode(node, button: button)
            return true
        } else if let toggle = view as? Toggle {
            buildToggleNode(node, toggle: toggle)
            return true
        } else if let segmented = view as? SegmentedControl {
            buildSegmentedControlNode(node, segmented: segmented)
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
        isSecure: Bool,
        existing: Node? = nil
    ) {
        node.isFocusable = true
        node[.getText] = getText
        node[.setText] = setText
        node[.placeholder] = placeholder
        node[.isSecure] = isSecure

        let bindingText = getText()
        reconcileDisplayBuffer(for: node, bindingText: bindingText, existing: existing)

        let displayText = node[.displayText] ?? bindingText
        if let existing = existing, let oldCursor = existing[.cursorPosition] {
            node[.cursorPosition] = min(oldCursor, displayText.count)
        } else {
            node[.cursorPosition] = displayText.count
        }

        let secureFieldWidth = 20

        node[.keyHandler] = makeInputFieldKeyHandler(for: node)
        node[.textInputHandler] = makeInputFieldTextHandler(for: node)
        node[.pasteInputHandler] = makeInputFieldPasteHandler(for: node)
        node.render = makeInputFieldRenderClosure(for: node, isSecure: isSecure)

        node.layout = { [weak node] proposal, _ in
            guard let node = node else { return (.zero, []) }
            let placeholder = node[.placeholder] ?? ""
            let store = node[.pasteStore] ?? [:]
            let rawDisplay = node[.displayText] ?? ""
            let visual = isSecure
                ? rawDisplay
                : PasteCollapse.visualString(displayText: rawDisplay, store: store)
            let shown = visual.isEmpty ? placeholder : visual
            let displayWidth = isSecure
                ? secureFieldWidth
                : terminalTextWidth(shown, replacingControlCharacters: true)
            let width = proposal.width.resolve(with: displayWidth)
            return (Size(width: width, height: 1), [])
        }
    }

    private func reconcileDisplayBuffer(
        for node: Node,
        bindingText: String,
        existing: Node?
    ) {
        if let existing,
           let previousDisplay = existing[.displayText]
        {
            let previousStore = existing[.pasteStore] ?? [:]
            let expanded = PasteCollapse.expand(displayText: previousDisplay, store: previousStore)
            if expanded == bindingText {
                node[.displayText] = previousDisplay
                node[.pasteStore] = previousStore
                return
            }
        }

        node[.displayText] = bindingText
        node[.pasteStore] = [:]
    }

    private static func syncBinding(from node: Node) {
        guard let setText = node[.setText] else { return }
        let displayText = node[.displayText] ?? ""
        let store = node[.pasteStore] ?? [:]
        setText(PasteCollapse.expand(displayText: displayText, store: store))
    }

    private func makeInputFieldKeyHandler(for node: Node) -> (KeyEvent) -> Void {
        return { [weak node] (event: KeyEvent) in
            guard let node = node else { return }
            var displayText = node[.displayText] ?? ""
            var store = node[.pasteStore] ?? [:]
            var cursor = node[.cursorPosition] ?? displayText.count
            NodeViewBuilder.applyKeyEdit(
                event.key,
                displayText: &displayText,
                cursor: &cursor,
                store: &store
            )

            node[.displayText] = displayText
            node[.pasteStore] = store
            node[.cursorPosition] = cursor
            NodeViewBuilder.syncBinding(from: node)
            Application.shared?.scheduleUpdate()
        }
    }

    private func makeInputFieldTextHandler(for node: Node) -> (String) -> Void {
        return { [weak node] insertedText in
            guard let node else { return }
            var displayText = node[.displayText] ?? ""
            var cursor = min(max(0, node[.cursorPosition] ?? displayText.count), displayText.count)
            PasteCollapse.insertRaw(insertedText, into: &displayText, cursor: &cursor)
            node[.displayText] = displayText
            node[.cursorPosition] = cursor
            NodeViewBuilder.syncBinding(from: node)
            Application.shared?.scheduleUpdate()
        }
    }

    private func makeInputFieldPasteHandler(for node: Node) -> (String) -> Void {
        return { [weak node] pastedText in
            guard let node else { return }
            var displayText = node[.displayText] ?? ""
            var store = node[.pasteStore] ?? [:]
            var cursor = min(max(0, node[.cursorPosition] ?? displayText.count), displayText.count)
            let isSecure = node[.isSecure] == true

            if isSecure || !PasteCollapse.shouldCollapse(pastedText) {
                PasteCollapse.insertRaw(pastedText, into: &displayText, cursor: &cursor)
            } else {
                _ = PasteCollapse.insertCollapsedPaste(
                    pastedText,
                    into: &displayText,
                    cursor: &cursor,
                    store: &store
                )
            }

            node[.displayText] = displayText
            node[.pasteStore] = store
            node[.cursorPosition] = cursor
            NodeViewBuilder.syncBinding(from: node)
            Application.shared?.scheduleUpdate()
        }
    }

    private static func applyKeyEdit(
        _ key: Key,
        displayText: inout String,
        cursor: inout Int,
        store: inout [String: String]
    ) {
        cursor = min(max(0, cursor), displayText.count)

        switch key {
        case .char(let c):
            PasteCollapse.insertRaw(String(c), into: &displayText, cursor: &cursor)
        case .backspace:
            PasteCollapse.backspace(displayText: &displayText, cursor: &cursor, store: &store)
        case .delete:
            PasteCollapse.deleteForward(displayText: &displayText, cursor: &cursor, store: &store)
        case .left:
            PasteCollapse.moveLeft(cursor: &cursor, in: displayText, store: store)
        case .right:
            PasteCollapse.moveRight(cursor: &cursor, in: displayText, store: store)
        case .home:
            cursor = 0
        case .end:
            cursor = displayText.count
        default:
            break
        }
    }

    private func makeInputFieldRenderClosure(for node: Node, isSecure: Bool) -> (
        Rect, inout RenderBuffer
    ) -> Void {
        return { [weak node] frame, buffer in
            guard let node = node else { return }
            let rawDisplay = node[.displayText] ?? ""
            let store = node[.pasteStore] ?? [:]
            let placeholder = node[.placeholder] ?? ""
            let shown: String

            if rawDisplay.isEmpty {
                shown = placeholder
            } else if isSecure {
                let expanded = PasteCollapse.expand(displayText: rawDisplay, store: store)
                shown = String(repeating: "\u{2022}", count: expanded.count)
            } else {
                shown = PasteCollapse.visualString(displayText: rawDisplay, store: store)
            }

            var style: Style
            if rawDisplay.isEmpty {
                style = Style().resolved(
                    with: node.environment,
                    fallbackForeground: .brightBlack
                )
                style.attributes.insert(.dim)
            } else {
                style = Style().resolved(with: node.environment)
            }

            buffer.drawClipped(
                shown,
                at: frame.origin,
                maxWidth: frame.width,
                style: style,
                replacingControlCharacters: true
            )
        }
    }

    private func buildTextFieldNode(_ node: Node, textField: TextField, existing: Node?) {
        buildInputFieldNode(
            node,
            getText: textField.getText,
            setText: textField.setText,
            placeholder: textField.placeholder,
            isSecure: false,
            existing: existing
        )
    }

    private func buildSecureFieldNode(_ node: Node, secureField: SecureField, existing: Node?) {
        buildInputFieldNode(
            node,
            getText: secureField.getText,
            setText: secureField.setText,
            placeholder: secureField.placeholder,
            isSecure: true,
            existing: existing
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

            var style = Style().resolved(
                with: node.environment,
                fallbackForeground: .white
            )
            if node.isFocused {
                style.attributes.insert(.reverse)
                style.attributes.insert(.bold)
            }

            let text = "[ \(label) ]"
            for (i, char) in text.prefix(frame.width).enumerated() {
                buffer.draw(char, at: Position(x: frame.x + i, y: frame.y), style: style)
            }
        }

        node.layout = { proposal, _ in
            let label = button.label
            let width = proposal.width.resolve(with: label.count + 4)  // "[ label ]"
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

            var style = Style().resolved(with: node.environment)
            if node.isFocused {
                style.attributes.insert(.reverse)
                style.attributes.insert(.bold)
            }

            for (i, char) in text.prefix(frame.width).enumerated() {
                buffer.draw(char, at: Position(x: frame.x + i, y: frame.y), style: style)
            }
        }

        node.layout = { proposal, _ in
            let width = proposal.width.resolve(with: toggle.label.count + 4)  // "[x] label"
            return (Size(width: width, height: 1), [])
        }
    }

}

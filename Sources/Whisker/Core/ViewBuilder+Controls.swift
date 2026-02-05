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
                let setText = node[.setText]
            else { return }

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

    private func makeInputFieldRenderClosure(for node: Node, isSecure: Bool) -> (
        Rect, inout RenderBuffer
    ) -> Void {
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

            var style: Style
            if text.isEmpty {
                style = Style().resolved(
                    with: node.environment,
                    fallbackForeground: .brightBlack
                )
                style.attributes.insert(.dim)
            } else {
                style = Style().resolved(with: node.environment)
            }

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

    // MARK: - Segmented Control

    private func buildSegmentedControlNode(_ node: Node, segmented: SegmentedControl) {
        node.isFocusable = true

        node[.keyHandler] = { (event: KeyEvent) in
            let options = segmented.options
            guard !options.isEmpty else { return }

            let current = min(max(segmented.selection.wrappedValue, 0), options.count - 1)
            var next = current

            switch event.key {
            case .left:
                if segmented.wraps && current == 0 {
                    next = options.count - 1
                } else {
                    next = max(0, current - 1)
                }
            case .right:
                if segmented.wraps && current == options.count - 1 {
                    next = 0
                } else {
                    next = min(options.count - 1, current + 1)
                }
            default:
                return
            }

            if next != segmented.selection.wrappedValue {
                segmented.selection.wrappedValue = next
                Application.shared?.scheduleUpdate()
            }
        }

        node.render = { [weak node] frame, buffer in
            guard let node = node else { return }
            let options = segmented.options
            guard !options.isEmpty else { return }

            let selectedIndex = min(max(segmented.selection.wrappedValue, 0), options.count - 1)
            let baseStyle = Style().resolved(with: node.environment)

            switch segmented.overflow {
            case .scroll:
                // Pre-compute segment start positions in content space
                var segmentStarts: [Int] = []
                var cx = 0
                for (index, option) in options.enumerated() {
                    segmentStarts.append(cx)
                    cx += option.count + 2
                    if index < options.count - 1 {
                        cx += 1
                    }
                }
                let contentWidth = cx

                // Compute scroll offset to keep selected segment visible
                var scrollOffset = 0
                let hasOverflow = contentWidth > frame.width
                // Reserve 1 char at each edge for scroll indicators
                let indicatorWidth = hasOverflow ? 1 : 0
                let viewportWidth = frame.width - (indicatorWidth * 2)

                if hasOverflow && viewportWidth > 0 {
                    let selStart = segmentStarts[selectedIndex]
                    let selEnd = selStart + options[selectedIndex].count + 2

                    if selEnd > scrollOffset + viewportWidth {
                        scrollOffset = selEnd - viewportWidth
                    }
                    if selStart < scrollOffset {
                        scrollOffset = selStart
                    }
                    scrollOffset = min(scrollOffset, max(0, contentWidth - viewportWidth))
                    scrollOffset = max(scrollOffset, 0)
                }

                // Draw left scroll indicator
                let showLeftIndicator = hasOverflow && scrollOffset > 0
                let showRightIndicator = hasOverflow && scrollOffset + viewportWidth < contentWidth
                let dimStyle = Style(foreground: .brightBlack)

                if hasOverflow {
                    let leftChar: Character = showLeftIndicator ? "\u{2039}" : " "
                    buffer.draw(leftChar, at: Position(x: frame.x, y: frame.y), style: dimStyle)
                }

                // Render segments in the viewport area
                let viewportX = frame.x + indicatorWidth
                var cursorX = viewportX - scrollOffset

                for (index, option) in options.enumerated() {
                    let segmentText = " \(option) "
                    var style = baseStyle
                    if index == selectedIndex {
                        style.attributes.insert(.reverse)
                    }
                    if index == selectedIndex && node.isFocused {
                        style = style.bold()
                    }

                    for char in segmentText {
                        if cursorX >= viewportX + viewportWidth { break }
                        if cursorX >= viewportX {
                            buffer.draw(char, at: Position(x: cursorX, y: frame.y), style: style)
                        }
                        cursorX += 1
                    }

                    if index < options.count - 1 {
                        if cursorX >= viewportX + viewportWidth { break }
                        if cursorX >= viewportX {
                            buffer.draw(" ", at: Position(x: cursorX, y: frame.y), style: .default)
                        }
                        cursorX += 1
                    }
                }

                // Draw right scroll indicator
                if hasOverflow {
                    let rightChar: Character = showRightIndicator ? "\u{203A}" : " "
                    buffer.draw(
                        rightChar, at: Position(x: frame.x + frame.width - 1, y: frame.y),
                        style: dimStyle)
                }

            case .wrap:
                let availableWidth = frame.width
                guard availableWidth > 0 else { return }

                // Lay out segments into lines
                var cursorX = frame.x
                var cursorY = frame.y

                for (index, option) in options.enumerated() {
                    let segmentWidth = option.count + 2

                    // Wrap to next line if this segment won't fit
                    if cursorX > frame.x && cursorX - frame.x + segmentWidth > availableWidth {
                        cursorX = frame.x
                        cursorY += 1
                    }

                    if cursorY >= frame.y + frame.height { break }

                    let segmentText = " \(option) "
                    var style = baseStyle
                    if index == selectedIndex {
                        style.attributes.insert(.reverse)
                    }
                    if index == selectedIndex && node.isFocused {
                        style = style.bold()
                    }

                    for char in segmentText {
                        if cursorX < frame.x + availableWidth {
                            buffer.draw(char, at: Position(x: cursorX, y: cursorY), style: style)
                        }
                        cursorX += 1
                    }

                    if index < options.count - 1 && cursorX < frame.x + availableWidth {
                        buffer.draw(" ", at: Position(x: cursorX, y: cursorY), style: .default)
                        cursorX += 1
                    }
                }
            }
        }

        node.layout = { proposal, _ in
            let options = segmented.options
            guard !options.isEmpty else { return (Size(width: 0, height: 1), []) }
            let spacing = options.count > 1 ? (options.count - 1) : 0
            let contentWidth = options.reduce(0) { $0 + $1.count + 2 } + spacing

            switch segmented.overflow {
            case .scroll:
                let width = proposal.width.resolve(with: contentWidth)
                return (Size(width: width, height: 1), [])

            case .wrap:
                let availableWidth = proposal.width.resolve(with: contentWidth)
                guard availableWidth > 0 else { return (Size(width: 0, height: 1), []) }

                // Calculate number of lines needed
                var lineCount = 1
                var x = 0
                for (index, option) in options.enumerated() {
                    let segmentWidth = option.count + 2
                    let spacingWidth = index < options.count - 1 ? 1 : 0

                    if x > 0 && x + segmentWidth > availableWidth {
                        lineCount += 1
                        x = segmentWidth + spacingWidth
                    } else {
                        x += segmentWidth + spacingWidth
                    }
                }

                return (Size(width: availableWidth, height: lineCount), [])
            }
        }
    }
}

// MARK: - Select List

extension NodeViewBuilder {

    func buildSelectListNode(_ node: Node, selectList: SelectList) {
        // An empty list has nothing to select, so it stays out of the focus
        // ring rather than becoming a stop that swallows keys and shows nothing.
        node.isFocusable = !selectList.options.isEmpty
        node[.keyHandler] = makeSelectListKeyHandler(for: selectList)

        node.render = { [weak node] frame, buffer in
            guard let node = node else { return }
            NodeViewBuilder.renderSelectList(
                selectList,
                isFocused: node.isFocused,
                baseStyle: Style().resolved(with: node.environment),
                frame: frame,
                buffer: &buffer
            )
        }

        node.layout = { proposal, _ in
            let window = selectList.window()
            let widest = selectList.options.reduce(0) { max($0, $1.count) }
            // Two columns for the pointer gutter, so rows line up whether or
            // not they are the selected one.
            let contentWidth = widest + 2
            return (
                Size(
                    width: proposal.width.resolve(with: contentWidth),
                    height: max(window.height, 1)
                ), []
            )
        }
    }

    private func makeSelectListKeyHandler(for selectList: SelectList) -> (KeyEvent) -> Bool {
        return { (event: KeyEvent) in
            guard !selectList.options.isEmpty else { return false }

            switch event.key {
            case .up, .down:
                guard let next = NodeViewBuilder.movedSelection(selectList, key: event.key) else {
                    return false
                }
                if next != selectList.selection.wrappedValue {
                    selectList.selection.wrappedValue = next
                    Application.shared?.scheduleUpdate()
                }
                return true
            case .enter:
                guard let onSubmit = selectList.onSubmit else { return false }
                onSubmit(selectList.clampedSelection)
                return true
            case .escape:
                guard let onCancel = selectList.onCancel else { return false }
                onCancel()
                return true
            default:
                return false
            }
        }
    }

    /// Where an arrow key moves the selection, or `nil` when the list declines
    /// the key at a boundary.
    ///
    /// Declining is what keeps the list out of the way: `handleKey` falls back
    /// to focus traversal, so an arrow at the end of the list moves on to the
    /// next control instead of being swallowed.
    private static func movedSelection(_ selectList: SelectList, key: Key) -> Int? {
        let current = selectList.clampedSelection
        let last = selectList.options.count - 1

        switch key {
        case .up:
            if current > 0 { return current - 1 }
            return selectList.wraps ? last : nil
        case .down:
            if current < last { return current + 1 }
            return selectList.wraps ? 0 : nil
        default:
            return nil
        }
    }

    // MARK: Rendering

    private static func renderSelectList(
        _ selectList: SelectList,
        isFocused: Bool,
        baseStyle: Style,
        frame: Rect,
        buffer: inout RenderBuffer
    ) {
        guard frame.width > 0, frame.height > 0, !selectList.options.isEmpty else { return }

        let window = selectList.window()
        let selected = selectList.clampedSelection
        let markerStyle = Style(foreground: .brightBlack)
        var row = frame.y
        let bottom = frame.y + frame.height

        func drawRow(_ text: String, style: Style) {
            guard row < bottom else { return }
            buffer.drawClipped(
                text, at: Position(x: frame.x, y: row), maxWidth: frame.width, style: style)
            row += 1
        }

        if window.showsMarkers {
            drawRow(window.hasMoreAbove ? "\u{25B2}" : " ", style: markerStyle)
        }

        for index in window.range {
            let isSelected = index == selected
            // The pointer only appears while focused, so an unfocused list
            // still shows what is selected without implying the arrow keys
            // are currently going to it.
            let prefix = isSelected && isFocused ? "\u{276F} " : "  "
            drawRow(prefix + selectList.options[index], style: rowStyle(
                baseStyle, isSelected: isSelected, isFocused: isFocused))
        }

        if window.showsMarkers {
            drawRow(window.hasMoreBelow ? "\u{25BC}" : " ", style: markerStyle)
        }
    }

    /// Selected rows invert; focus adds bold on top, matching `SegmentedControl`.
    private static func rowStyle(_ base: Style, isSelected: Bool, isFocused: Bool) -> Style {
        var style = base
        if isSelected {
            style.attributes.insert(.reverse)
            if isFocused { style.attributes.insert(.bold) }
        }
        return style
    }
}

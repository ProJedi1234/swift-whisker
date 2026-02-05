// MARK: - Segmented Control

private struct SegmentedRenderContext {
    let options: [String]
    let selectedIndex: Int
    let isFocused: Bool
    let baseStyle: Style
}

extension NodeViewBuilder {

    func buildSegmentedControlNode(_ node: Node, segmented: SegmentedControl) {
        node.isFocusable = true
        node[.keyHandler] = makeSegmentedControlKeyHandler(for: segmented)

        node.render = { [weak node] frame, buffer in
            guard let node = node else { return }
            let options = segmented.options
            guard !options.isEmpty else { return }

            let selectedIndex = min(max(segmented.selection.wrappedValue, 0), options.count - 1)
            let ctx = SegmentedRenderContext(
                options: options, selectedIndex: selectedIndex,
                isFocused: node.isFocused,
                baseStyle: Style().resolved(with: node.environment)
            )

            switch segmented.overflow {
            case .scroll:
                NodeViewBuilder.renderSegmentedScroll(ctx, frame: frame, buffer: &buffer)
            case .wrap:
                NodeViewBuilder.renderSegmentedWrap(ctx, frame: frame, buffer: &buffer)
            }
        }

        node.layout = { proposal, _ in
            NodeViewBuilder.layoutSegmentedControl(
                options: segmented.options, overflow: segmented.overflow, proposal: proposal
            )
        }
    }

    private func makeSegmentedControlKeyHandler(
        for segmented: SegmentedControl
    ) -> (KeyEvent) -> Void {
        return { (event: KeyEvent) in
            let options = segmented.options
            guard !options.isEmpty else { return }

            let current = min(max(segmented.selection.wrappedValue, 0), options.count - 1)
            var next = current

            switch event.key {
            case .left:
                next =
                    segmented.wraps && current == 0
                    ? options.count - 1 : max(0, current - 1)
            case .right:
                next =
                    segmented.wraps && current == options.count - 1
                    ? 0 : min(options.count - 1, current + 1)
            default:
                return
            }

            if next != segmented.selection.wrappedValue {
                segmented.selection.wrappedValue = next
                Application.shared?.scheduleUpdate()
            }
        }
    }

    // MARK: Scroll Rendering

    private static func renderSegmentedScroll(
        _ ctx: SegmentedRenderContext, frame: Rect, buffer: inout RenderBuffer
    ) {
        let (segmentStarts, contentWidth) = segmentPositions(ctx.options)
        let hasOverflow = contentWidth > frame.width
        let indicatorWidth = hasOverflow ? 1 : 0
        let viewportWidth = frame.width - (indicatorWidth * 2)

        let selWidth = ctx.options[ctx.selectedIndex].count + 2
        let scrollOffset = Self.scrollOffset(
            selStart: segmentStarts[ctx.selectedIndex], selWidth: selWidth,
            contentWidth: contentWidth, viewportWidth: viewportWidth, hasOverflow: hasOverflow
        )

        // Draw scroll indicators
        if hasOverflow {
            let dimStyle = Style(foreground: .brightBlack)
            buffer.draw(
                scrollOffset > 0 ? "\u{2039}" : " ",
                at: Position(x: frame.x, y: frame.y), style: dimStyle
            )
            buffer.draw(
                scrollOffset + viewportWidth < contentWidth ? "\u{203A}" : " ",
                at: Position(x: frame.x + frame.width - 1, y: frame.y), style: dimStyle
            )
        }

        // Render segments in the viewport
        let viewportX = frame.x + indicatorWidth
        var cursorX = viewportX - scrollOffset
        for (index, option) in ctx.options.enumerated() {
            let style = segmentStyle(ctx.baseStyle, index: index, ctx: ctx)
            for char in " \(option) " {
                if cursorX >= viewportX + viewportWidth { break }
                if cursorX >= viewportX {
                    buffer.draw(char, at: Position(x: cursorX, y: frame.y), style: style)
                }
                cursorX += 1
            }
            if index < ctx.options.count - 1 {
                if cursorX >= viewportX + viewportWidth { break }
                if cursorX >= viewportX {
                    buffer.draw(" ", at: Position(x: cursorX, y: frame.y), style: .default)
                }
                cursorX += 1
            }
        }
    }

    private static func segmentPositions(_ options: [String]) -> ([Int], Int) {
        var starts: [Int] = []
        var cx = 0
        for (index, option) in options.enumerated() {
            starts.append(cx)
            cx += option.count + 2
            if index < options.count - 1 { cx += 1 }
        }
        return (starts, cx)
    }

    private static func scrollOffset(
        selStart: Int, selWidth: Int, contentWidth: Int,
        viewportWidth: Int, hasOverflow: Bool
    ) -> Int {
        guard hasOverflow, viewportWidth > 0 else { return 0 }
        var offset = 0
        if selStart + selWidth > viewportWidth { offset = selStart + selWidth - viewportWidth }
        if selStart < offset { offset = selStart }
        return min(offset, max(0, contentWidth - viewportWidth))
    }

    // MARK: Wrap Rendering

    private static func renderSegmentedWrap(
        _ ctx: SegmentedRenderContext, frame: Rect, buffer: inout RenderBuffer
    ) {
        guard frame.width > 0 else { return }
        var cursorX = frame.x
        var cursorY = frame.y

        for (index, option) in ctx.options.enumerated() {
            let segmentWidth = option.count + 2
            if cursorX > frame.x && cursorX - frame.x + segmentWidth > frame.width {
                cursorX = frame.x
                cursorY += 1
            }
            if cursorY >= frame.y + frame.height { break }

            let style = segmentStyle(ctx.baseStyle, index: index, ctx: ctx)
            for char in " \(option) " {
                if cursorX < frame.x + frame.width {
                    buffer.draw(char, at: Position(x: cursorX, y: cursorY), style: style)
                }
                cursorX += 1
            }
            if index < ctx.options.count - 1 && cursorX < frame.x + frame.width {
                buffer.draw(" ", at: Position(x: cursorX, y: cursorY), style: .default)
                cursorX += 1
            }
        }
    }

    // MARK: Helpers

    private static func segmentStyle(
        _ base: Style, index: Int, ctx: SegmentedRenderContext
    ) -> Style {
        var style = base
        if index == ctx.selectedIndex {
            style.attributes.insert(.reverse)
            if ctx.isFocused { style.attributes.insert(.bold) }
        }
        return style
    }

    private static func layoutSegmentedControl(
        options: [String], overflow: SegmentedControl.Overflow, proposal: ProposedSize
    ) -> (Size, [(Node, Rect)]) {
        guard !options.isEmpty else { return (Size(width: 0, height: 1), []) }
        let spacing = options.count > 1 ? (options.count - 1) : 0
        let contentWidth = options.reduce(0) { $0 + $1.count + 2 } + spacing

        switch overflow {
        case .scroll:
            return (Size(width: proposal.width.resolve(with: contentWidth), height: 1), [])
        case .wrap:
            let available = proposal.width.resolve(with: contentWidth)
            guard available > 0 else { return (Size(width: 0, height: 1), []) }
            var lineCount = 1
            var x = 0
            for (index, option) in options.enumerated() {
                let w = option.count + 2 + (index < options.count - 1 ? 1 : 0)
                if x > 0 && x + option.count + 2 > available {
                    lineCount += 1
                    x = w
                } else {
                    x += w
                }
            }
            return (Size(width: available, height: lineCount), [])
        }
    }
}

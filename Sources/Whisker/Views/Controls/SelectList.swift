/// A vertical list of options that lets you move a selection with the arrow keys.
///
/// `SelectList` is built entirely on the public `.focusable()` and
/// `.onKeyPress(action:)` modifiers — it composes ordinary `Text` rows rather
/// than using dedicated node build logic, demonstrating that custom focusable
/// controls can be written outside the framework.
///
/// The list joins the focus ring like any built-in control. While focused,
/// `.up`/`.down` move the selection (consumed, so focus traversal doesn't
/// fire); at the ends the selection clamps by default, or wraps around when
/// `wraps` is `true`, matching `SegmentedControl`. When there are more options
/// than `visibleRows`, a sliding window keeps the selection visible with
/// `▲`/`▼` overflow indicators (dropped when `visibleRows < 3`, where they
/// would crowd out the options), so the list never grows beyond `visibleRows`
/// lines — important in inline mode, where there is no viewport clipping.
public struct SelectList: View {
    let options: [String]
    let selection: Binding<Int>
    let wraps: Bool
    let visibleRows: Int

    /// Create a select list with string options and an index binding.
    ///
    /// - Parameters:
    ///   - options: The rows to choose between.
    ///   - selection: The selected index. Out-of-range values (e.g. after the
    ///     options array shrinks) are clamped, never crash.
    ///   - wraps: Whether the selection wraps around at the ends instead of
    ///     clamping, like `SegmentedControl`'s `wraps`.
    ///   - visibleRows: Maximum number of terminal rows the list occupies.
    public init(
        _ options: [String],
        selection: Binding<Int>,
        wraps: Bool = false,
        visibleRows: Int = 10
    ) {
        self.options = options
        self.selection = selection
        self.wraps = wraps
        self.visibleRows = max(1, visibleRows)
    }

    public var body: some View {
        let rows = windowRows()
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rows.count) { index in
                rows[index]
            }
        }
        .focusable(!options.isEmpty)
        .onKeyPress(action: handleKey)
    }

    // MARK: - Key Handling

    private func handleKey(_ event: KeyEvent) -> KeyPressResult {
        guard !options.isEmpty else { return .ignored }

        let current = min(max(selection.wrappedValue, 0), options.count - 1)
        let next: Int
        switch event.key {
        case .up:
            next = wraps && current == 0 ? options.count - 1 : max(0, current - 1)
        case .down:
            next = wraps && current == options.count - 1 ? 0 : min(options.count - 1, current + 1)
        default:
            return .ignored
        }

        if next != selection.wrappedValue {
            selection.wrappedValue = next
            Application.shared?.scheduleUpdate()
        }
        // Consumed even at the boundary so focus traversal doesn't fire.
        return .handled
    }

    // MARK: - Rows

    /// Build the visible rows: a sliding window over the options plus
    /// overflow indicator rows when the list doesn't fit in `visibleRows`.
    /// Indicator rows are only emitted when `visibleRows >= 3` so the total
    /// row count never exceeds `visibleRows`.
    private func windowRows() -> [Text] {
        guard !options.isEmpty else { return [] }

        let count = options.count
        let selected = min(max(selection.wrappedValue, 0), count - 1)
        let hasOverflow = count > visibleRows
        let showsIndicators = hasOverflow && visibleRows >= 3
        let windowSize = hasOverflow ? (showsIndicators ? visibleRows - 2 : visibleRows) : count
        let offset = min(max(0, selected - windowSize + 1), count - windowSize)

        var rows: [Text] = []
        if showsIndicators {
            rows.append(indicatorRow(offset > 0 ? "▲" : " "))
        }
        for index in offset..<(offset + windowSize) {
            rows.append(optionRow(options[index], isSelected: index == selected))
        }
        if showsIndicators {
            rows.append(indicatorRow(offset + windowSize < count ? "▼" : " "))
        }
        return rows
    }

    private func indicatorRow(_ glyph: String) -> Text {
        Text(glyph).foregroundColor(.brightBlack)
    }

    private func optionRow(_ option: String, isSelected: Bool) -> Text {
        guard isSelected else { return Text("  \(option)") }
        var row = Text("\u{276F} \(option)")
        row.style.attributes.insert(.reverse)
        row.style.attributes.insert(.bold)
        return row
    }
}

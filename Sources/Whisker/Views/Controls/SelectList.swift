/// A vertical list of options that lets you move a selection with the arrow keys.
///
/// `SelectList` is built entirely on the public `.focusable()` and
/// `.onKeyPress(_:)` modifiers — it composes ordinary `Text` rows rather than
/// using dedicated node build logic, demonstrating that custom focusable
/// controls can be written outside the framework.
///
/// The list joins the focus ring like any built-in control. While focused,
/// `.up`/`.down` move the selection (consumed, so focus traversal doesn't
/// fire); at the ends the selection clamps, matching `SegmentedControl`'s
/// default. When there are more options than `visibleRows`, a sliding window
/// keeps the selection visible with `▲`/`▼` overflow indicators, so the list
/// never grows beyond `visibleRows` lines — important in inline mode, where
/// there is no viewport clipping.
public struct SelectList: View {
    let options: [String]
    let selection: Binding<Int>
    let visibleRows: Int

    /// Create a select list with string options and an index binding.
    ///
    /// - Parameters:
    ///   - options: The rows to choose between.
    ///   - selection: The selected index. Out-of-range values (e.g. after the
    ///     options array shrinks) are clamped, never crash.
    ///   - visibleRows: Maximum number of terminal rows the list occupies.
    public init(_ options: [String], selection: Binding<Int>, visibleRows: Int = 10) {
        self.options = options
        self.selection = selection
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
        .onKeyPress(handleKey)
    }

    // MARK: - Key Handling

    private func handleKey(_ event: KeyEvent) -> Bool {
        guard !options.isEmpty else { return false }

        let current = min(max(selection.wrappedValue, 0), options.count - 1)
        let next: Int
        switch event.key {
        case .up:
            next = max(0, current - 1)
        case .down:
            next = min(options.count - 1, current + 1)
        default:
            return false
        }

        if next != selection.wrappedValue {
            selection.wrappedValue = next
            Application.shared?.scheduleUpdate()
        }
        // Consumed even at the boundary so focus traversal doesn't fire.
        return true
    }

    // MARK: - Rows

    /// Build the visible rows: a sliding window over the options plus
    /// overflow indicator rows when the list doesn't fit in `visibleRows`.
    private func windowRows() -> [Text] {
        guard !options.isEmpty else { return [] }

        let count = options.count
        let selected = min(max(selection.wrappedValue, 0), count - 1)
        let hasOverflow = count > visibleRows
        let windowSize = hasOverflow ? max(1, visibleRows - 2) : count
        let offset = min(max(0, selected - windowSize + 1), count - windowSize)

        var rows: [Text] = []
        if hasOverflow {
            rows.append(indicatorRow(offset > 0 ? "▲" : " "))
        }
        for index in offset..<(offset + windowSize) {
            rows.append(optionRow(options[index], isSelected: index == selected))
        }
        if hasOverflow {
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

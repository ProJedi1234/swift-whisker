/// A vertical list of options that lets you move a selection with the arrow keys.
///
/// The list joins the focus ring like any other control. While focused, `.up`
/// and `.down` move the selection; `.enter` submits it and `.escape` cancels,
/// each only when the matching handler was supplied. When there are more
/// options than `visibleRows`, a sliding window keeps the selection in view
/// with `▲`/`▼` overflow markers, and the list never occupies more than
/// `visibleRows` lines — important in inline mode, which has no viewport
/// clipping.
///
/// At the ends of the list an arrow key moves focus onward instead of doing
/// nothing, so the list never traps someone navigating by keyboard. Set
/// `wraps` to cycle within the list instead.
///
///     SelectList(
///         repos,
///         selection: $index,
///         onSubmit: { picked = repos[$0]; Application.shared?.quit() },
///         onCancel: { Application.shared?.quit() }
///     )
public struct SelectList: View {
    public typealias Body = Never

    let options: [String]
    let selection: Binding<Int>
    let wraps: Bool
    let visibleRows: Int
    let onSubmit: ((Int) -> Void)?
    let onCancel: (() -> Void)?

    /// Create a select list with string options and an index binding.
    ///
    /// - Parameters:
    ///   - options: The rows to choose between.
    ///   - selection: The selected index. Out-of-range values — after the
    ///     options array shrinks, say — are clamped rather than trapping.
    ///   - wraps: Whether the selection cycles at the ends instead of handing
    ///     focus onward, like `SegmentedControl`'s `wraps`.
    ///   - visibleRows: The most terminal rows the list may occupy.
    ///   - onSubmit: Called with the selected index when `.enter` is pressed.
    ///     Without it `.enter` is left to the surrounding view.
    ///   - onCancel: Called when `.escape` is pressed. Without it `.escape` is
    ///     left to the surrounding view.
    public init(
        _ options: [String],
        selection: Binding<Int>,
        wraps: Bool = false,
        visibleRows: Int = 10,
        onSubmit: ((Int) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.options = options
        self.selection = selection
        self.wraps = wraps
        self.visibleRows = max(1, visibleRows)
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public var body: Never {
        fatalError("SelectList has no body")
    }

    // MARK: - Windowing

    /// The slice of options on screen, and whether more sit above or below.
    struct Window {
        let range: Range<Int>
        let showsMarkers: Bool
        let hasMoreAbove: Bool
        let hasMoreBelow: Bool

        /// Rows occupied on screen, never more than the list's `visibleRows`.
        var height: Int { range.count + (showsMarkers ? 2 : 0) }
    }

    var clampedSelection: Int {
        guard !options.isEmpty else { return 0 }
        return min(max(selection.wrappedValue, 0), options.count - 1)
    }

    /// Derive the visible window from the selection alone — no stored scroll
    /// offset — so it behaves the same travelling up as down. The selection
    /// stays centred except near the ends. Markers cost a row each, so they
    /// are only drawn when `visibleRows` can spare them.
    func window() -> Window {
        guard !options.isEmpty else {
            return Window(
                range: 0..<0, showsMarkers: false, hasMoreAbove: false, hasMoreBelow: false)
        }

        let count = options.count
        guard count > visibleRows else {
            return Window(
                range: 0..<count, showsMarkers: false, hasMoreAbove: false, hasMoreBelow: false)
        }

        let showsMarkers = visibleRows >= 3
        let size = showsMarkers ? visibleRows - 2 : visibleRows
        let offset = min(max(0, clampedSelection - size / 2), count - size)

        return Window(
            range: offset..<(offset + size),
            showsMarkers: showsMarkers,
            hasMoreAbove: offset > 0,
            hasMoreBelow: offset + size < count
        )
    }
}

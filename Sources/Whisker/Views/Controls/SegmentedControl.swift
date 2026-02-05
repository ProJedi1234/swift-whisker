/// A segmented control that lets you select between multiple options
public struct SegmentedControl: View {
    public typealias Body = Never

    /// How the control handles content that exceeds available width
    public enum Overflow {
        /// Scroll horizontally with indicators showing more content
        case scroll
        /// Wrap segments onto multiple lines
        case wrap
    }

    let options: [String]
    let selection: Binding<Int>
    let wraps: Bool
    let overflow: Overflow

    /// Create a segmented control with string options and an index binding
    public init(
        _ options: [String],
        selection: Binding<Int>,
        wraps: Bool = false,
        overflow: Overflow = .scroll
    ) {
        self.options = options
        self.selection = selection
        self.wraps = wraps
        self.overflow = overflow
    }

    public var body: Never {
        fatalError("SegmentedControl has no body")
    }
}

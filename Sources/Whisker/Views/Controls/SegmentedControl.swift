/// A segmented control that lets you select between multiple options
public struct SegmentedControl: View {
    public typealias Body = Never

    let options: [String]
    let selection: Binding<Int>

    /// Create a segmented control with string options and an index binding
    public init(_ options: [String], selection: Binding<Int>) {
        self.options = options
        self.selection = selection
    }

    public var body: Never {
        fatalError("SegmentedControl has no body")
    }
}

/// A view that creates views from an underlying collection of identified data
public struct ForEach<Data, ID, Content>: View where Data: RandomAccessCollection, ID: Hashable, Content: View {
    public typealias Body = Never

    let data: Data
    let id: KeyPath<Data.Element, ID>
    let content: (Data.Element) -> Content

    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.id = id
        self.content = content
    }

    public var body: Never {
        fatalError("ForEach has no body")
    }
}

// Convenience initializer when Data.Element conforms to Identifiable
extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
    public init(
        _ data: Data,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.id = \.id
        self.content = content
    }
}

// Convenience for ranges
extension ForEach where Data == Range<Int>, ID == Int {
    public init(
        _ data: Range<Int>,
        @ViewBuilder content: @escaping (Int) -> Content
    ) {
        self.data = data
        self.id = \.self
        self.content = content
    }
}

import Foundation

/// Protocol for types that can compute layout
public protocol Layout {
    /// Calculate the size this layout needs given constraints and children
    func sizeThatFits(
        proposal: ProposedSize,
        children: [LayoutChild]
    ) -> Size

    /// Place children within the given bounds
    func placeChildren(
        in bounds: Rect,
        children: [LayoutChild]
    )
}

/// A child in a layout context
public struct LayoutChild {
    public let node: Node
    public var size: Size = .zero
    public var position: Position = .zero

    public init(node: Node) {
        self.node = node
    }

    /// Calculate preferred size for this child
    public func sizeThatFits(_ proposal: ProposedSize) -> Size {
        if let layoutFn = node.layout {
            let (size, _) = layoutFn(proposal, node.children)
            return size
        }
        return .zero
    }
}

public struct VStackLayout: Layout {
    public let alignment: HorizontalAlignment
    public let spacing: Int

    public init(alignment: HorizontalAlignment = .center, spacing: Int = 0) {
        self.alignment = alignment
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedSize, children: [LayoutChild]) -> Size {
        var totalHeight = 0
        var maxWidth = 0

        for (index, var child) in children.enumerated() {
            let childSize = child.sizeThatFits(ProposedSize(
                width: proposal.width,
                height: .unconstrained
            ))
            child.size = childSize
            maxWidth = max(maxWidth, childSize.width)
            totalHeight += childSize.height
            if index < children.count - 1 {
                totalHeight += spacing
            }
        }

        return Size(
            width: proposal.width.resolve(with: maxWidth),
            height: proposal.height.resolve(with: totalHeight)
        )
    }

    public func placeChildren(in bounds: Rect, children: [LayoutChild]) {
        var y = bounds.y

        for child in children {
            let childSize = child.sizeThatFits(ProposedSize(
                width: .exactly(bounds.width),
                height: .unconstrained
            ))

            let x: Int
            switch alignment {
            case .leading:
                x = bounds.x
            case .center:
                x = bounds.x + (bounds.width - childSize.width) / 2
            case .trailing:
                x = bounds.x + bounds.width - childSize.width
            }

            child.node.frame = Rect(x: x, y: y, width: childSize.width, height: childSize.height)
            y += childSize.height + spacing
        }
    }
}

public struct HStackLayout: Layout {
    public let alignment: VerticalAlignment
    public let spacing: Int

    public init(alignment: VerticalAlignment = .center, spacing: Int = 0) {
        self.alignment = alignment
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedSize, children: [LayoutChild]) -> Size {
        var totalWidth = 0
        var maxHeight = 0

        for (index, var child) in children.enumerated() {
            let childSize = child.sizeThatFits(ProposedSize(
                width: .unconstrained,
                height: proposal.height
            ))
            child.size = childSize
            maxHeight = max(maxHeight, childSize.height)
            totalWidth += childSize.width
            if index < children.count - 1 {
                totalWidth += spacing
            }
        }

        return Size(
            width: proposal.width.resolve(with: totalWidth),
            height: proposal.height.resolve(with: maxHeight)
        )
    }

    public func placeChildren(in bounds: Rect, children: [LayoutChild]) {
        var x = bounds.x

        for child in children {
            let childSize = child.sizeThatFits(ProposedSize(
                width: .unconstrained,
                height: .exactly(bounds.height)
            ))

            let y: Int
            switch alignment {
            case .top:
                y = bounds.y
            case .center:
                y = bounds.y + (bounds.height - childSize.height) / 2
            case .bottom:
                y = bounds.y + bounds.height - childSize.height
            }

            child.node.frame = Rect(x: x, y: y, width: childSize.width, height: childSize.height)
            x += childSize.width + spacing
        }
    }
}

public struct ZStackLayout: Layout {
    public let alignment: Alignment

    public init(alignment: Alignment = .center) {
        self.alignment = alignment
    }

    public func sizeThatFits(proposal: ProposedSize, children: [LayoutChild]) -> Size {
        var maxWidth = 0
        var maxHeight = 0

        for var child in children {
            let childSize = child.sizeThatFits(proposal)
            child.size = childSize
            maxWidth = max(maxWidth, childSize.width)
            maxHeight = max(maxHeight, childSize.height)
        }

        return Size(
            width: proposal.width.resolve(with: maxWidth),
            height: proposal.height.resolve(with: maxHeight)
        )
    }

    public func placeChildren(in bounds: Rect, children: [LayoutChild]) {
        for child in children {
            let childSize = child.sizeThatFits(ProposedSize(bounds.size))

            let x: Int
            switch alignment.horizontal {
            case .leading:
                x = bounds.x
            case .center:
                x = bounds.x + (bounds.width - childSize.width) / 2
            case .trailing:
                x = bounds.x + bounds.width - childSize.width
            }

            let y: Int
            switch alignment.vertical {
            case .top:
                y = bounds.y
            case .center:
                y = bounds.y + (bounds.height - childSize.height) / 2
            case .bottom:
                y = bounds.y + bounds.height - childSize.height
            }

            child.node.frame = Rect(x: x, y: y, width: childSize.width, height: childSize.height)
        }
    }
}

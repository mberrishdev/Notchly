import CoreGraphics

/// Size of the Idle handle for a given set of chips.
///
/// Kept as pure arithmetic, separate from the view, because the window frame has to be
/// known before anything is laid out — and because getting it wrong is the difference
/// between a handle that hugs the bezel and one that clips its own contents.
struct IdleHandleLayout: Equatable {
    /// How far the handle protrudes from the Edge.
    var depth: CGFloat
    /// How far it runs along the Edge.
    var extent: CGFloat
    /// False when there are no chips, i.e. the plain line.
    var showsContent: Bool

    static let spacing: CGFloat = 5
    static let endPadding: CGFloat = 9

    static func resolve(chips: [IdleChip],
                        edge: ScreenEdge,
                        lineThickness: CGFloat,
                        lineLength: CGFloat,
                        contentThickness: CGFloat,
                        widgetCount: Int) -> IdleHandleLayout {
        guard !chips.isEmpty else {
            return IdleHandleLayout(depth: max(2, lineThickness),
                                    extent: max(12, lineLength),
                                    showsContent: false)
        }

        let horizontal = edge.growsHorizontally
        let content = chips.reduce(CGFloat.zero) {
            $0 + $1.extent(growsHorizontally: horizontal, widgetCount: widgetCount)
        }
        let gaps = spacing * CGFloat(max(0, chips.count - 1))
        return IdleHandleLayout(depth: max(18, contentThickness),
                                extent: max(28, content + gaps + endPadding * 2),
                                showsContent: true)
    }
}

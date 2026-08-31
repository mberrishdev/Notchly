import CoreGraphics

/// Where the panel should dock for a given pointer position.
///
/// Pulled out of the drag handler so the rule — nearest edge in *proportional* terms,
/// then position along that edge — can be reasoned about and tested on its own.
struct PanelPlacement: Equatable {
    var edge: ScreenEdge
    /// 0 is the top or left of the display, 1 the bottom or right.
    var alignment: Double

    static func resolve(pointer: CGPoint, in frame: CGRect) -> PanelPlacement? {
        guard frame.width > 0, frame.height > 0 else { return nil }

        // Distances are normalised by the screen's own dimensions, so on a wide display
        // the left and right edges still win inside their own halves rather than the
        // top and bottom edges claiming almost everything.
        let candidates: [(ScreenEdge, CGFloat)] = [
            (.leading, (pointer.x - frame.minX) / frame.width),
            (.trailing, (frame.maxX - pointer.x) / frame.width),
            (.top, (frame.maxY - pointer.y) / frame.height),
            (.bottom, (pointer.y - frame.minY) / frame.height)
        ]
        guard let edge = candidates.min(by: { $0.1 < $1.1 })?.0 else { return nil }

        let alignment: CGFloat = edge.growsHorizontally
            ? (frame.maxY - pointer.y) / frame.height
            : (pointer.x - frame.minX) / frame.width

        return PanelPlacement(edge: edge, alignment: Double(min(max(alignment, 0), 1)))
    }
}

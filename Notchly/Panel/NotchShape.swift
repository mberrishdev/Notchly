import SwiftUI

struct NotchShape: Shape, Animatable {
    var edge: ScreenEdge
    /// Rounding on the two corners furthest from the screen edge.
    var cornerRadius: CGFloat
    /// Radius of the concave flare where the panel meets the edge.
    var inverseRadius: CGFloat

    init(edge: ScreenEdge, cornerRadius: CGFloat, inverseRadius: CGFloat) {
        self.edge = edge
        self.cornerRadius = cornerRadius
        self.inverseRadius = inverseRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, inverseRadius) }
        set { cornerRadius = newValue.first; inverseRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        // Canonical space is always "hanging from the top"; for the side edges the
        // canonical rect is the transposed one.
        let canonicalSize = edge.growsHorizontally
            ? CGSize(width: rect.height, height: rect.width)
            : rect.size
        var path = Self.canonicalPath(size: canonicalSize,
                                      cornerRadius: cornerRadius,
                                      inverseRadius: inverseRadius)
        path = path.applying(Self.transform(for: edge, in: rect.size))
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }

    /// A top-docked notch: concave flares at `y == 0`, rounded corners at the bottom.
    private static func canonicalPath(size: CGSize, cornerRadius: CGFloat, inverseRadius: CGFloat) -> Path {
        let w = size.width
        let h = size.height
        // Clamp so extreme settings (or mid-animation values) can never self-intersect.
        let ir = max(0, min(inverseRadius, w / 2, h))
        let cr = max(0, min(cornerRadius, (w - 2 * ir) / 2, h - ir))

        var path = Path()
        guard w > 0, h > 0 else { return path }

        path.move(to: CGPoint(x: 0, y: 0))
        // Flare in from the edge to the left wall of the body.
        path.addQuadCurve(to: CGPoint(x: ir, y: ir), control: CGPoint(x: ir, y: 0))
        path.addLine(to: CGPoint(x: ir, y: h - cr))
        path.addQuadCurve(to: CGPoint(x: ir + cr, y: h), control: CGPoint(x: ir, y: h))
        path.addLine(to: CGPoint(x: w - ir - cr, y: h))
        path.addQuadCurve(to: CGPoint(x: w - ir, y: h - cr), control: CGPoint(x: w - ir, y: h))
        path.addLine(to: CGPoint(x: w - ir, y: ir))
        // Flare back out to the edge.
        path.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - ir, y: 0))
        path.closeSubpath()
        return path
    }

    /// Maps canonical (top-docked) coordinates onto the requested edge.
    private static func transform(for edge: ScreenEdge, in size: CGSize) -> CGAffineTransform {
        switch edge {
        case .top:
            return .identity
        case .bottom:
            return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        case .trailing:
            return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.width, ty: 0)
        case .leading:
            return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        }
    }
}

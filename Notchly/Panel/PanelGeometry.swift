import AppKit
import SwiftUI

struct PanelGeometry {
    var edge: ScreenEdge
    var screenFrame: CGRect
    var alignment: Double
    var bodyDepth: CGFloat
    var bodyExtent: CGFloat
    var handleDepth: CGFloat
    var handleExtent: CGFloat
    var cornerRadius: CGFloat
    var edgeInset: CGFloat
    /// False when the handle is the plain line, which is styled differently.
    var handleShowsContent: Bool

    /// Room reserved around the open panel for its drop shadow.
    static let shadowMargin: CGFloat = 34
    /// Slack around the idle handle so the pointer doesn't need pixel precision.
    static let hoverBuffer: CGFloat = 22

    init(settings: NotchlySettings, screen: NSScreen, enabledWidgetCount: Int = 0) {
        edge = settings.edge
        screenFrame = screen.frame
        alignment = settings.alignment
        bodyDepth = CGFloat(settings.panelWidth)
        bodyExtent = CGFloat(settings.panelHeight)
        let handle = IdleHandleLayout.resolve(chips: settings.handleChips,
                                             edge: settings.edge,
                                             lineThickness: CGFloat(settings.handleThickness),
                                             lineLength: CGFloat(settings.handleLength),
                                             contentThickness: CGFloat(settings.handleContentThickness),
                                             widgetCount: enabledWidgetCount)
        handleDepth = handle.depth
        handleExtent = handle.extent
        handleShowsContent = handle.showsContent
        cornerRadius = CGFloat(settings.cornerRadius)
        edgeInset = CGFloat(settings.edgeInset)

        // For the horizontal edges the panel's "depth" is its height, so swap what the
        // width/height settings mean rather than making the user re-tune them.
        if !edge.growsHorizontally {
            bodyDepth = CGFloat(settings.panelHeight)
            bodyExtent = CGFloat(settings.panelWidth)
        }
    }

    var expandedInverseRadius: CGFloat { min(14, cornerRadius * 0.6) }
    var handleInverseRadius: CGFloat { handleShowsContent ? min(9, handleDepth * 0.3) : min(6, handleDepth * 1.2) }
    var handleCornerRadius: CGFloat { handleShowsContent ? min(handleDepth / 2, 13) : min(handleDepth / 2 + 2, 6) }

    /// Size of the drawn shape, including the concave flares that overhang the body.
    func shapeSize(expanded: Bool) -> CGSize {
        let depth = expanded ? bodyDepth : handleDepth
        let extent = (expanded ? bodyExtent : handleExtent) + 2 * (expanded ? expandedInverseRadius : handleInverseRadius)
        return edge.growsHorizontally ? CGSize(width: depth, height: extent) : CGSize(width: extent, height: depth)
    }

    /// Centre of the panel along the edge, in Cocoa screen coordinates.
    func edgeCenter(expanded: Bool) -> CGFloat {
        let margin = (expanded ? Self.shadowMargin : Self.hoverBuffer)
        let ir = expanded ? expandedInverseRadius : handleInverseRadius
        let half = (expanded ? bodyExtent : handleExtent) / 2 + ir + margin

        if edge.growsHorizontally {
            let lo = screenFrame.minY + half
            let hi = screenFrame.maxY - half
            guard hi > lo else { return screenFrame.midY }
            // alignment 0 == top of the display, which is maxY in Cocoa coordinates.
            return hi - CGFloat(alignment) * (hi - lo)
        } else {
            let lo = screenFrame.minX + half
            let hi = screenFrame.maxX - half
            guard hi > lo else { return screenFrame.midX }
            return lo + CGFloat(alignment) * (hi - lo)
        }
    }

    func windowFrame(expanded: Bool) -> CGRect {
        let margin = expanded ? Self.shadowMargin : Self.hoverBuffer
        let depth = (expanded ? bodyDepth : handleDepth) + margin
        let ir = expanded ? expandedInverseRadius : handleInverseRadius
        let extent = (expanded ? bodyExtent : handleExtent) + 2 * ir + 2 * margin
        let center = edgeCenter(expanded: expanded)

        switch edge {
        case .trailing:
            return CGRect(x: screenFrame.maxX - depth + edgeInset,
                          y: center - extent / 2,
                          width: depth, height: extent)
        case .leading:
            return CGRect(x: screenFrame.minX - edgeInset,
                          y: center - extent / 2,
                          width: depth, height: extent)
        case .top:
            return CGRect(x: center - extent / 2,
                          y: screenFrame.maxY - depth + edgeInset,
                          width: extent, height: depth)
        case .bottom:
            return CGRect(x: center - extent / 2,
                          y: screenFrame.minY - edgeInset,
                          width: extent, height: depth)
        }
    }

    /// SwiftUI alignment that pins content to the docked edge.
    var contentAlignment: Alignment {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }
}

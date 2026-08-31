import SwiftUI

struct PanelRootView: View {
    @EnvironmentObject private var panel: PanelController
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var environment: AppEnvironment
    @State private var dragExceededThreshold = false

    var body: some View {
        let geometry = panel.geometry
        let expanded = panel.isExpanded
        let size = geometry.shapeSize(expanded: expanded)
        let corner = expanded ? geometry.cornerRadius : geometry.handleCornerRadius
        let inverse = expanded ? geometry.expandedInverseRadius : geometry.handleInverseRadius
        let shape = NotchShape(edge: geometry.edge, cornerRadius: corner, inverseRadius: inverse)

        ZStack(alignment: geometry.contentAlignment) {
            Color.clear
            ZStack {
                surface(shape: shape)
                if expanded {
                    PanelContentView()
                        .padding(contentInsets(inverse: inverse))
                        .transition(.opacity.animation(.easeOut(duration: 0.18).delay(0.06)))
                } else if geometry.handleShowsContent {
                    IdleHandleView(edge: geometry.edge, chips: settings.settings.handleChips)
                        .padding(contentInsets(inverse: inverse))
                        .opacity(idleContentOpacity)
                } else {
                    handleAccent
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .overlay(
                shape.stroke(expanded ? Theme.hairlineStrong : Color.white.opacity(0.14), lineWidth: 0.75)
            )
            .background(shadow(shape: shape, expanded: expanded))
            .scaleEffect(handleScale, anchor: anchor(for: geometry.edge))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: geometry.contentAlignment)
        // While idle the whole (small) window is the drag target, so the handle doesn't
        // demand pixel-perfect aim. Once open, only the header grip moves the panel.
        .contentShape(Rectangle())
        .gesture(repositionGesture, including: expanded ? .subviews : .all)
        .animation(Theme.openSpring(reduced: settings.settings.reduceMotion), value: expanded)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: panel.isHandleHighlighted)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: panel.isDragging)
    }

    /// The shadow is drawn as a blurred copy of the outline rather than with
    /// `.shadow()`, which flattens a view containing a `Material` to its bounding box
    /// and casts a rectangle around the panel instead of following its corners.
    private func shadow(shape: NotchShape, expanded: Bool) -> some View {
        let offset = shadowOffset(panel.geometry.edge)
        return shape
            .fill(Color.black.opacity(expanded ? 0.5 : 0.3))
            .blur(radius: expanded ? 16 : 4)
            .offset(x: offset.width, y: offset.height)
            // Blur bleeds past the frame, and a background is not clipped to it.
            .allowsHitTesting(false)
    }

    /// Drag the handle to slide the panel along its edge, or across the midpoint of
    /// the display to re-dock it to another edge. A press that never moves is a tap,
    /// which is what opens the panel.
    private var repositionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let distance = max(abs(value.translation.width), abs(value.translation.height))
                if !dragExceededThreshold, distance > 4 {
                    dragExceededThreshold = true
                    panel.beginDrag()
                }
                if dragExceededThreshold { panel.dragToPointer() }
            }
            .onEnded { _ in
                if dragExceededThreshold {
                    panel.endDrag()
                } else if !panel.isExpanded {
                    panel.handleTapped()
                }
                dragExceededThreshold = false
            }
    }

    @ViewBuilder
    private func surface(shape: NotchShape) -> some View {
        ZStack {
            switch settings.settings.material {
            case .glass:
                Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                Rectangle().fill(Theme.shellBackground.opacity(0.55))
            case .tinted:
                Rectangle().fill(Theme.shellBackground.opacity(0.86))
            case .solid:
                Rectangle().fill(Theme.shellBackground.opacity(0.985))
            }
            // A faint inner highlight along the top keeps the surface from looking flat.
            LinearGradient(colors: [Color.white.opacity(0.055), .clear],
                           startPoint: .top, endPoint: .center)
                .blendMode(.plusLighter)
        }
        .opacity(settings.settings.opacity)
    }

    /// While idle, the handle picks up a hint of the accent colour on hover.
    private var handleAccent: some View {
        LinearGradient(colors: panel.isHandleHighlighted || panel.isDragging
                       ? [settings.settings.accentColor.opacity(0.9), settings.settings.accentColor.opacity(0.45)]
                       : [Color.white.opacity(0.22), Color.white.opacity(0.1)],
                       startPoint: .top, endPoint: .bottom)
            .opacity(settings.settings.showsHandleWhenIdle || panel.isHandleHighlighted ? 1 : 0.28)
    }

    /// The bare line grows on hover to advertise itself. A handle with content stays
    /// put and brightens instead — scaling text just makes it blurry.
    private var handleScale: CGFloat {
        guard !panel.isExpanded, !panel.geometry.handleShowsContent else { return 1 }
        if panel.isDragging { return 1.3 }
        return panel.isHandleHighlighted ? 1.12 : 1
    }

    private var idleContentOpacity: Double {
        if panel.isHandleHighlighted || panel.isDragging { return 1 }
        return settings.settings.showsHandleWhenIdle ? 0.82 : 0.4
    }

    /// Keeps content clear of the concave flares at either end of the panel.
    private func contentInsets(inverse: CGFloat) -> EdgeInsets {
        let pad = max(inverse, 6)
        switch panel.geometry.edge {
        case .leading, .trailing:
            return EdgeInsets(top: pad, leading: 0, bottom: pad, trailing: 0)
        case .top, .bottom:
            return EdgeInsets(top: 0, leading: pad, bottom: 0, trailing: pad)
        }
    }

    private func shadowOffset(_ edge: ScreenEdge) -> CGSize {
        switch edge {
        case .trailing: return CGSize(width: -8, height: 4)
        case .leading: return CGSize(width: 8, height: 4)
        case .top: return CGSize(width: 0, height: 10)
        case .bottom: return CGSize(width: 0, height: -10)
        }
    }

    private func anchor(for edge: ScreenEdge) -> UnitPoint {
        switch edge {
        case .trailing: return .trailing
        case .leading: return .leading
        case .top: return .top
        case .bottom: return .bottom
        }
    }
}

/// Header, scrolling widget stack, footer.

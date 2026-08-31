import SwiftUI

struct PanelPreview: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var showExpanded = true

    var body: some View {
        GeometryReader { geo in
            let screen = CGRect(origin: .zero, size: geo.size).insetBy(dx: 20, dy: 12)
            let scale = min(screen.width / 1512, screen.height / 982)
            let config = settings.settings
            let depth = CGFloat(config.edge.growsHorizontally ? config.panelWidth : config.panelHeight) * scale
            let extent = CGFloat(config.edge.growsHorizontally ? config.panelHeight : config.panelWidth) * scale
            // Same layout the real handle uses, so the preview can't drift from it.
            let handle = IdleHandleLayout.resolve(chips: config.handleChips,
                                                  edge: config.edge,
                                                  lineThickness: CGFloat(config.handleThickness),
                                                  lineLength: CGFloat(config.handleLength),
                                                  contentThickness: CGFloat(config.handleContentThickness),
                                                  widgetCount: config.slots.filter(\.isEnabled).count)
            let handleDepth = max(1.5, handle.depth * scale)
            let handleExtent = handle.extent * scale
            let inverse = min(14, CGFloat(config.cornerRadius) * 0.6) * scale
            let handleInverse = handle.showsContent
                ? min(9, handle.depth * 0.3)
                : min(6, handle.depth * 1.2)

            let size = showExpanded
                ? shapeSize(edge: config.edge, depth: depth, extent: extent + 2 * inverse)
                : shapeSize(edge: config.edge, depth: handleDepth,
                            extent: handleExtent + 2 * handleInverse * scale)

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [Theme.plateTop, Theme.plateBottom],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: screen.width, height: screen.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .overlay(alignment: alignment(for: config.edge)) {
                        let shape = NotchShape(
                            edge: config.edge,
                            cornerRadius: showExpanded
                                ? CGFloat(config.cornerRadius) * scale
                                : min(handle.depth / 2, 13) * scale,
                            inverseRadius: showExpanded ? inverse : handleInverse * scale
                        )
                        shape
                            .fill(Color.black.opacity(0.92))
                            .overlay(shape.stroke(config.accentColor.opacity(0.5), lineWidth: 0.75))
                            .frame(width: size.width, height: size.height)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showExpanded)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: config)
            .onTapGesture { showExpanded.toggle() }
            .help("Click to preview the idle handle")
        }
    }

    private func shapeSize(edge: ScreenEdge, depth: CGFloat, extent: CGFloat) -> CGSize {
        edge.growsHorizontally ? CGSize(width: depth, height: extent) : CGSize(width: extent, height: depth)
    }

    private func alignment(for edge: ScreenEdge) -> Alignment {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }
}

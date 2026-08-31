import SwiftUI
import UniformTypeIdentifiers

struct PinnedAppTile: View {
    let app: LaunchableApp
    let icon: NSImage
    let onLaunch: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onLaunch) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 30, height: 30)
                        .scaleEffect(isHovering ? 1.1 : 1)
                    if isHovering {
                        Button(action: onRemove) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white, Color.black.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -5)
                        .transition(.opacity)
                        .help("Unpin \(app.name)")
                    }
                }
                .frame(height: 32)
                Text(app.name)
                    .font(.system(size: 8.5))
                    .foregroundStyle(isHovering ? Theme.primaryText : Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.white.opacity(0.07) : .clear)
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isHovering = hovering }
        }
        .help(app.name)
    }
}

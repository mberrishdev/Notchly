import AppKit
import SwiftUI

struct HoverRow<Content: View>: View {
    var isSelected = false
    var cornerRadius: CGFloat = 8
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            content()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillColor)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovering = hovering }
        }
    }

    private var fillColor: Color {
        if isSelected { return Color.white.opacity(0.14) }
        return isHovering ? Color.white.opacity(0.08) : .clear
    }
}

/// Filled line chart for the CPU / network history strips.

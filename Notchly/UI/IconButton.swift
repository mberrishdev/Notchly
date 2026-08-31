import AppKit
import SwiftUI

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 12
    var diameter: CGFloat = 26
    var isProminent = false
    var help: String? = nil
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isProminent ? Color.black.opacity(0.85) : Theme.primaryText.opacity(isHovering ? 1 : 0.72))
                .frame(width: diameter, height: diameter)
                .background(
                    Circle().fill(background)
                )
                .scaleEffect(isPressed ? 0.9 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.07)) { isPressed = true } }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.12)) { isPressed = false } }
        )
        .help(help ?? "")
    }

    private var background: Color {
        if isProminent { return settings.settings.accentColor.opacity(isHovering ? 1 : 0.9) }
        return Color.white.opacity(isHovering ? 0.12 : 0.06)
    }
}

/// Row that lights up on hover — the workhorse for lists in the launcher and clipboard.

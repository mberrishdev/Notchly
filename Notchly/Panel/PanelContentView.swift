import SwiftUI

struct PanelContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var registry: WidgetRegistry
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var panel: PanelController
    @State private var isDraggingHeader = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            widgetStack
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(settings.settings.accentColor)
                .frame(width: 6, height: 6)
            Text("Notchly")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.primaryText)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isDraggingHeader ? settings.settings.accentColor : Theme.tertiaryText)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .gesture(headerDragGesture)
                .help("Drag to move the panel to another edge")

            Spacer(minLength: 8)

            IconButton(symbol: settings.settings.isPinned ? "pin.fill" : "pin",
                       size: 10, diameter: 22,
                       help: settings.settings.isPinned ? "Unpin panel" : "Keep panel open") {
                panel.togglePinned()
            }
            IconButton(symbol: "slider.horizontal.3", size: 10, diameter: 22, help: "Settings") {
                SettingsWindowController.shared.show(environment: environment)
            }
            IconButton(symbol: "xmark", size: 9, diameter: 22, help: "Close") {
                panel.close(immediate: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 9)
    }

    private var headerDragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { _ in
                if !isDraggingHeader { isDraggingHeader = true; panel.beginDrag() }
                panel.dragToPointer()
            }
            .onEnded { _ in
                isDraggingHeader = false
                panel.endDrag()
            }
    }

    private var widgetStack: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: Theme.cardSpacing) {
                let slots = registry.activeSlots()
                if slots.isEmpty {
                    emptyPanel
                } else {
                    ForEach(slots, id: \.slot.id) { entry in
                        registry.view(for: entry.descriptor)
                            .id(entry.slot.id)
                    }
                }
                Color.clear.frame(height: 2)
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var emptyPanel: some View {
        VStack(spacing: 10) {
            EmptyStateView(symbol: "square.dashed",
                           title: "No widgets yet",
                           detail: "Add built-in widgets or drop your own into the widgets folder.")
            Button {
                SettingsWindowController.shared.show(environment: environment, tab: .widgets)
            } label: {
                Text("Open Widget Settings")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(settings.settings.accentColor))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 20)
    }
}

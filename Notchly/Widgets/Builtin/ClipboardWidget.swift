import SwiftUI

struct ClipboardWidget: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var service: ClipboardService
    @EnvironmentObject private var settings: SettingsStore

    @State private var focusToken = 0
    @State private var copiedID: UUID?
    @State private var query = ""

    private var prefs: WidgetPreferences { WidgetPreferences(widgetID: "clipboard", environment: environment) }

    private var visible: [ClipboardItem] {
        let all = service.items
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = trimmed.isEmpty ? all : all.filter {
            $0.text.lowercased().contains(trimmed) || ($0.sourceName?.lowercased().contains(trimmed) ?? false)
        }
        return Array(filtered.prefix(prefs.int("visibleCount", default: 6)))
    }

    var body: some View {
        WidgetCard(title: "Clipboard", symbol: "doc.on.clipboard",
                   content: { content },
                   accessory: {
                       HStack(spacing: 6) {
                           if !service.items.isEmpty {
                               Text("\(service.items.count)")
                                   .font(.system(size: 9.5, weight: .medium))
                                   .monospacedDigit()
                                   .foregroundStyle(Theme.tertiaryText)
                           }
                           Button { service.setEnabled(!service.isEnabled) } label: {
                               Image(systemName: service.isEnabled ? "record.circle" : "pause.circle")
                                   .font(.system(size: 10))
                                   .foregroundStyle(service.isEnabled ? settings.settings.accentColor : Theme.tertiaryText)
                           }
                           .buttonStyle(.plain)
                           .help(service.isEnabled ? "Pause clipboard capture" : "Resume clipboard capture")
                       }
                   })
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if service.items.count > 3 { searchField }

            if visible.isEmpty {
                EmptyStateView(symbol: "doc.on.clipboard",
                               title: query.isEmpty ? "Nothing copied yet" : "No matches",
                               detail: query.isEmpty ? "Copy something and it lands here." : nil)
            } else {
                VStack(spacing: 3) {
                    ForEach(visible) { item in
                        row(item)
                    }
                }
                if !service.items.filter({ !$0.isPinned }).isEmpty {
                    Button { service.clearAll(keepPinned: true) } label: {
                        Text("Clear unpinned")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
        .onChange(of: query) { _, value in
            environment.setHoldOpen(!value.isEmpty, owner: "clipboard")
        }
        .onDisappear { environment.setHoldOpen(false, owner: "clipboard") }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
            PanelSearchField(text: $query,
                             placeholder: "Filter history",
                             focusToken: focusToken,
                             onCancel: { query = "" })
            .frame(height: 16)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.05)))
        .contentShape(Rectangle())
        .onTapGesture { focusToken += 1 }
    }

    private func row(_ item: ClipboardItem) -> some View {
        HoverRow {
            service.copyToPasteboard(item)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { copiedID = item.id }
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                if copiedID == item.id { withAnimation { copiedID = nil } }
            }
        } content: {
            HStack(spacing: 8) {
                icon(for: item)
                VStack(alignment: .leading, spacing: 1) {
                    if item.kind == .image, let image = service.image(for: item) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 120, maxHeight: 34, alignment: .leading)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Text(item.preview)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    HStack(spacing: 5) {
                        if let source = item.sourceName {
                            Text(source)
                        }
                        Text(item.createdAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        if item.kind == .text && item.lineCount > 1 {
                            Text("\(item.lineCount) lines")
                        }
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                trailing(item)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
        }
        .contextMenu {
            Button("Copy") { service.copyToPasteboard(item) }
            Button(item.isPinned ? "Unpin" : "Pin") { service.togglePin(item) }
            if item.kind == .url, let url = URL(string: item.text) {
                Button("Open Link") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("Delete", role: .destructive) { service.remove(item) }
        }
    }

    @ViewBuilder
    private func icon(for item: ClipboardItem) -> some View {
        Group {
            switch item.kind {
            case .url: Image(systemName: "link")
            case .image: Image(systemName: "photo")
            case .file: Image(systemName: "doc")
            case .color:
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: item.text) ?? .gray)
                    .frame(width: 11, height: 11)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
            case .text: Image(systemName: "text.alignleft")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Theme.tertiaryText)
        .frame(width: 14)
    }

    @ViewBuilder
    private func trailing(_ item: ClipboardItem) -> some View {
        if copiedID == item.id {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(settings.settings.accentColor)
                .transition(.scale.combined(with: .opacity))
        } else if item.isPinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 8.5))
                .foregroundStyle(Theme.tertiaryText)
                .rotationEffect(.degrees(45))
        }
    }
}

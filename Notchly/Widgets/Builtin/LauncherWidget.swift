import SwiftUI
import UniformTypeIdentifiers

struct LauncherWidget: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var catalog: AppCatalog
    @EnvironmentObject private var settings: SettingsStore

    @State private var query = ""
    @State private var selection = 0
    @State private var focusToken = 0
    @State private var isDropTargeted = false

    private var prefs: WidgetPreferences { WidgetPreferences(widgetID: "launcher", environment: environment) }
    private var columns: Int { max(3, min(6, prefs.int("columns", default: 5))) }

    private var pinned: [LaunchableApp] {
        let ids = environment.widgetSetting(key: "pinned", widgetID: "launcher")?
            .arrayValue?.compactMap(\.stringValue) ?? Self.defaultPinned
        return ids.compactMap { catalog.app(withID: $0) }
    }

    private var results: [LaunchableApp] {
        catalog.search(query, limit: 6)
    }

    var body: some View {
        WidgetCard(title: "Launcher", symbol: "square.grid.2x2",
                   content: { content },
                   accessory: {
                       if catalog.isIndexing {
                           ProgressView().controlSize(.mini).scaleEffect(0.7)
                       } else {
                           Text("\(catalog.apps.count)")
                               .font(.system(size: 9.5, weight: .medium))
                               .monospacedDigit()
                               .foregroundStyle(Theme.tertiaryText)
                       }
                   })
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchField
            if query.isEmpty {
                grid
            } else {
                resultList
            }
        }
        .onChange(of: query) { _, newValue in
            selection = 0
            environment.setHoldOpen(!newValue.isEmpty, owner: "launcher")
        }
        .onDisappear { environment.setHoldOpen(false, owner: "launcher") }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
            PanelSearchField(text: $query,
                             placeholder: "Search apps",
                             focusToken: focusToken,
                             onMove: moveSelection,
                             onSubmit: launchSelection,
                             onCancel: clearOrClose)
            .frame(height: 18)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(query.isEmpty ? Theme.hairline : settings.settings.accentColor.opacity(0.5), lineWidth: 0.75)
        )
        .contentShape(Rectangle())
        .onTapGesture { focusToken += 1 }
    }

    /// Escape clears the field first, and only closes the panel once it is empty.
    private func clearOrClose() {
        if query.isEmpty {
            NotificationCenter.default.post(name: .notchlyRequestClose, object: nil)
        } else {
            query = ""
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    private func launchSelection() {
        guard results.indices.contains(selection) else { return }
        launch(results[selection])
    }

    private func launch(_ app: LaunchableApp) {
        catalog.launch(app)
        query = ""
        NotificationCenter.default.post(name: .notchlyRequestClose, object: nil)
    }

    private var resultList: some View {
        VStack(spacing: 2) {
            if results.isEmpty {
                EmptyStateView(symbol: "questionmark.app.dashed", title: "No apps match “\(query)”")
            } else {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, app in
                    HoverRow(isSelected: index == selection) { launch(app) } content: {
                        HStack(spacing: 8) {
                            Image(nsImage: catalog.icon(for: app))
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(app.name)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if index == selection {
                                Image(systemName: "return")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 8) {
            if pinned.isEmpty {
                EmptyStateView(symbol: "plus.app.dashed",
                               title: "No pinned apps",
                               detail: "Drag apps here, or search above.")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 8) {
                    ForEach(pinned) { app in
                        PinnedAppTile(app: app,
                                      icon: catalog.icon(for: app),
                                      onLaunch: { launch(app) },
                                      onRemove: { unpin(app) })
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isDropTargeted ? settings.settings.accentColor : .clear,
                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .padding(-4)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            handled = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension == "app" else { return }
                Task { @MainActor in pin(url: url) }
            }
        }
        return handled
    }

    private func pin(url: URL) {
        let identifier = Bundle(url: url)?.bundleIdentifier ?? url.path
        var ids = environment.widgetSetting(key: "pinned", widgetID: "launcher")?
            .arrayValue?.compactMap(\.stringValue) ?? Self.defaultPinned
        guard !ids.contains(identifier) else { return }
        ids.append(identifier)
        environment.setWidgetSetting(.array(ids.map(JSONValue.string)), key: "pinned", widgetID: "launcher")
        if catalog.app(withID: identifier) == nil { catalog.refresh() }
    }

    private func unpin(_ app: LaunchableApp) {
        var ids = environment.widgetSetting(key: "pinned", widgetID: "launcher")?
            .arrayValue?.compactMap(\.stringValue) ?? Self.defaultPinned
        ids.removeAll { $0 == app.id }
        environment.setWidgetSetting(.array(ids.map(JSONValue.string)), key: "pinned", widgetID: "launcher")
    }

    /// A sensible starting set so the grid isn't empty on first launch.
    private static let defaultPinned = [
        "com.apple.finder", "com.apple.Safari", "com.apple.mail",
        "com.apple.Terminal", "com.apple.systempreferences"
    ]
}

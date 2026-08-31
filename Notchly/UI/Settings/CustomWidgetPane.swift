import AppKit
import SwiftUI

struct CustomWidgetPane: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var store: WebWidgetStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var newWidgetName = ""
    @State private var inspecting: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Widgets folder",
                            footer: "Each widget is a folder with a widget.json and an HTML entry point. Save a file and Notchly reloads it — no restart, no rebuild.") {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(AppPaths.widgetsDirectory.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button("Reveal") { store.revealInFinder() }
                        .controlSize(.small)
                }

                Divider()

                HStack(spacing: 8) {
                    TextField("New widget name", text: $newWidgetName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    Button("Create") {
                        if let folder = store.createStarterWidget(named: newWidgetName) {
                            newWidgetName = ""
                            NSWorkspace.shared.selectFile(folder.appendingPathComponent("index.html").path,
                                                          inFileViewerRootedAtPath: folder.path)
                        }
                    }
                    .controlSize(.small)
                    Spacer(minLength: 8)
                    Button("Reload All") { store.reloadAll() }
                        .controlSize(.small)
                    Button("Reinstall Examples") { store.copyExamples(overwrite: true) }
                        .controlSize(.small)
                }

                Toggle("Enable the web inspector", isOn: Binding(
                    get: { settings.settings.enableWebInspector },
                    set: { newValue in
                        settings.settings.enableWebInspector = newValue
                        // Nudge every widget so the flag reaches web views already on screen.
                        store.reloadAll()
                    }
                ))
                .toggleStyle(.switch)
                .help("Right-click a widget and choose Inspect Element for Safari's developer tools.")
            }

            if !store.failures.isEmpty {
                SettingsSection(title: "Could not load") {
                    ForEach(store.failures) { failure in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.system(size: 11))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(failure.folderURL.lastPathComponent)
                                    .font(.system(size: 12, weight: .medium))
                                Text(failure.reason)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Button("Show") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: failure.folderURL.path)
                            }
                            .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            SettingsSection(title: "Installed (\(store.packages.count))") {
                if store.packages.isEmpty {
                    Text("Nothing installed yet. Create a starter widget above to see the shape of one.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(store.packages) { package in
                            packageRow(package)
                        }
                    }
                }
            }

            SettingsSection(title: "API",
                            footer: "Everything on window.notchly returns a promise. Permissions your widget hasn't been granted reject with a readable message.") {
                APIReference()
            }
        }
    }

    private func packageRow(_ package: WebWidgetPackage) -> some View {
        let descriptor = package.descriptor
        let isInspecting = inspecting == package.id
        let logs = environment.widgetLogs[package.id] ?? []

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: descriptor.symbol)
                    .frame(width: 18)
                    .foregroundStyle(settings.settings.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(descriptor.name).font(.system(size: 12, weight: .medium))
                        if let version = descriptor.version {
                            Text("v\(version)")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(descriptor.summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)

                if isInPanel(package.id) {
                    Text("In panel")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(settings.settings.accentColor)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(settings.settings.accentColor.opacity(0.15)))
                } else {
                    Button("Add to Panel") {
                        settings.settings.slots.append(WidgetSlot(kind: .web, widgetID: package.id))
                    }
                    .controlSize(.small)
                }

                Button {
                    withAnimation(.easeOut(duration: 0.18)) { inspecting = isInspecting ? nil : package.id }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isInspecting ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 5)

            if isInspecting {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(package.folderURL.lastPathComponent)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let author = descriptor.author {
                            Text("by \(author)").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 8)
                        Button("Open Folder") {
                            NSWorkspace.shared.selectFile(package.entryURL.path,
                                                          inFileViewerRootedAtPath: package.folderURL.path)
                        }
                        .controlSize(.small)
                        Button("Reload") { store.bumpRevision(for: package.id) }
                            .controlSize(.small)
                    }

                    WidgetPermissionList(descriptor: descriptor)

                    if !descriptor.settingsSchema.isEmpty {
                        Divider()
                        Text("SETTINGS")
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(.tertiary)
                        WidgetSettingsForm(descriptor: descriptor)
                    }

                    Divider()
                    HStack {
                        Text("LOG").font(.system(size: 9.5, weight: .semibold)).tracking(0.5).foregroundStyle(.tertiary)
                        Spacer()
                        Button("Clear") { environment.clearWidgetLog(widgetID: package.id) }
                            .controlSize(.mini)
                            .disabled(logs.isEmpty)
                    }
                    if logs.isEmpty {
                        Text("Nothing logged. Call notchly.log() from your widget, or throw an error.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(logs.suffix(40).enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(maxHeight: 110)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.18)))
                    }
                }
                .padding(.leading, 28)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func isInPanel(_ id: String) -> Bool {
        settings.settings.slots.contains { $0.widgetID == id }
    }
}

/// Compact, copyable reference for the bridge API.

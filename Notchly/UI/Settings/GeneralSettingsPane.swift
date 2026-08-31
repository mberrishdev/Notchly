import AppKit
import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var environment: AppEnvironment
    @State private var loginItemError: String?

    private var config: Binding<NotchlySettings> { $settings.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Placement") {
                LabeledControl(label: "Dock to") {
                    Picker("", selection: config.edge) {
                        ForEach(ScreenEdge.allCases) { edge in
                            Label(edge.label, systemImage: edge.symbol).tag(edge)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                }

                ValueSlider(label: "Position along edge",
                            help: settings.settings.edge.growsHorizontally ? "0% is the left of the display." : "0% is the top of the display.",
                            value: Binding(get: { settings.settings.alignment * 100 },
                                           set: { settings.settings.alignment = $0 / 100 }),
                            range: 0...100, step: 1, unit: "%")

                LabeledControl(label: "Display", help: "Follow the pointer, or pin the panel to one screen.") {
                    Picker("", selection: Binding(
                        get: { settings.settings.preferredScreenID ?? -1 },
                        set: { settings.settings.preferredScreenID = $0 == -1 ? nil : $0 }
                    )) {
                        Text("Screen with pointer").tag(-1)
                        ForEach(NSScreen.screens, id: \.notchlyDisplayID) { screen in
                            if let id = screen.notchlyDisplayID {
                                Text(screen.notchlyName).tag(id)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                ValueSlider(label: "Edge offset",
                            help: "Nudges the panel away from the screen edge.",
                            value: config.edgeInset, range: 0...40)
            }

            SettingsSection(title: "Opening") {
                LabeledControl(label: "Activation", help: settings.settings.activation.detail) {
                    Picker("", selection: config.activation) {
                        ForEach(ActivationMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                if settings.settings.activation == .hover {
                    ValueSlider(label: "Open delay",
                                value: Binding(get: { settings.settings.openDelay * 1000 },
                                               set: { settings.settings.openDelay = $0 / 1000 }),
                                range: 0...800, step: 10, unit: "ms")
                }

                ValueSlider(label: "Close delay",
                            help: "How long the panel waits after the pointer leaves.",
                            value: Binding(get: { settings.settings.closeDelay * 1000 },
                                           set: { settings.settings.closeDelay = $0 / 1000 }),
                            range: 0...2000, step: 20, unit: "ms")

                Toggle("Close when clicking outside", isOn: config.closeOnOutsideClick)
                Toggle("Keep the panel open", isOn: config.isPinned)
            }

            SettingsSection(title: "Shortcut") {
                LabeledControl(label: "Toggle panel", help: "Works everywhere, no Accessibility access needed.") {
                    HotKeyRecorder(spec: config.hotkey)
                }
            }

            SettingsSection(title: "System", footer: loginItemError) {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.settings.launchAtLogin },
                    set: { newValue in
                        settings.settings.launchAtLogin = newValue
                        loginItemError = LoginItem.set(newValue)
                        if loginItemError != nil { settings.settings.launchAtLogin = LoginItem.isEnabled }
                    }
                ))
                Toggle("Show menu bar icon", isOn: config.showsMenuBarIcon)

                LabeledControl(label: "Clipboard history",
                               help: "Older unpinned entries are dropped once the limit is hit.") {
                    Stepper(value: config.clipboardHistoryLimit, in: 20...500, step: 10) {
                        Text("\(settings.settings.clipboardHistoryLimit) entries")
                            .font(.system(size: 11))
                            .monospacedDigit()
                    }
                    .frame(width: 160)
                }
                Toggle("Capture images to clipboard history", isOn: config.clipboardCapturesImages)
            }
        }
        .onAppear { settings.settings.launchAtLogin = LoginItem.isEnabled }
        .toggleStyle(.switch)
    }
}

/// Click, then press the combination you want. Escape cancels; Delete clears.

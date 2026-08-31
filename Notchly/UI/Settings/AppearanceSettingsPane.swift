import SwiftUI

struct AppearanceSettingsPane: View {
    @EnvironmentObject private var settings: SettingsStore
    private var config: Binding<NotchlySettings> { $settings.settings }

    private static let accentPresets = ["#6E9BFF", "#7FD1AE", "#FFC46B", "#FF8A9B", "#C79BFF", "#8FE3F5", "#E8E8EA"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Preview") {
                PanelPreview()
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            }

            SettingsSection(title: "Surface") {
                LabeledControl(label: "Material") {
                    Picker("", selection: config.material) {
                        ForEach(PanelMaterial.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }

                ValueSlider(label: "Opacity",
                            value: Binding(get: { settings.settings.opacity * 100 },
                                           set: { settings.settings.opacity = $0 / 100 }),
                            range: 40...100, step: 1, unit: "%")

                LabeledControl(label: "Accent") {
                    HStack(spacing: 6) {
                        ForEach(Self.accentPresets, id: \.self) { hex in
                            let isSelected = settings.settings.accentHex.caseInsensitiveCompare(hex) == .orderedSame
                            Button {
                                settings.settings.accentHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex) ?? .accentColor)
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Circle().strokeBorder(
                                            isSelected ? Color.primary : Color.primary.opacity(0.15),
                                            lineWidth: isSelected ? 2 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        ColorPicker("", selection: Binding(
                            get: { settings.settings.accentColor },
                            set: { settings.settings.accentHex = $0.hexString }
                        ), supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 40)
                    }
                }
            }

            SettingsSection(title: "Shape",
                            footer: "Width and height describe how far the panel reaches from its edge and how long it runs along it.") {
                ValueSlider(label: "Panel width", value: config.panelWidth, range: 240...560)
                ValueSlider(label: "Panel height", value: config.panelHeight, range: 200...900)
                ValueSlider(label: "Corner radius", value: config.cornerRadius, range: 0...44)
            }

            IdleHandleSection()

            SettingsSection(title: "Motion") {
                Toggle("Show the handle when idle", isOn: config.showsHandleWhenIdle)
                Toggle("Reduce motion", isOn: config.reduceMotion)
            }

            HStack {
                Spacer()
                Button("Reset Appearance") { resetAppearance() }
            }
        }
        .toggleStyle(.switch)
    }

    private func resetAppearance() {
        let defaults = NotchlySettings()
        settings.settings.material = defaults.material
        settings.settings.opacity = defaults.opacity
        settings.settings.accentHex = defaults.accentHex
        settings.settings.panelWidth = defaults.panelWidth
        settings.settings.panelHeight = defaults.panelHeight
        settings.settings.cornerRadius = defaults.cornerRadius
        settings.settings.handleThickness = defaults.handleThickness
        settings.settings.handleLength = defaults.handleLength
        settings.settings.handleChips = defaults.handleChips
        settings.settings.handleContentThickness = defaults.handleContentThickness
        settings.settings.showsHandleWhenIdle = defaults.showsHandleWhenIdle
        settings.settings.reduceMotion = defaults.reduceMotion
    }
}

/// Scale model of the panel on its display, so shape settings can be judged without
/// closing the window and hunting for the real thing.

import SwiftUI
import UniformTypeIdentifiers

struct WidgetSettingsForm: View {
    let descriptor: WidgetDescriptor
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(descriptor.settingsSchema) { field in
                control(for: field)
            }
        }
    }

    @ViewBuilder
    private func control(for field: WidgetSettingField) -> some View {
        switch field.kind {
        case .boolean:
            Toggle(field.label, isOn: boolBinding(field))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))

        case .string:
            LabeledControl(label: field.label, help: field.help) {
                TextField("", text: stringBinding(field))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .font(.system(size: 11.5))
            }

        case .number:
            LabeledControl(label: field.label, help: field.help) {
                HStack(spacing: 8) {
                    Slider(value: doubleBinding(field),
                           in: (field.minimum ?? 0)...(field.maximum ?? 100),
                           step: 1)
                    .frame(width: 140)
                    Text("\(Int(doubleBinding(field).wrappedValue.rounded()))")
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }

        case .select:
            LabeledControl(label: field.label, help: field.help) {
                Picker("", selection: stringBinding(field)) {
                    ForEach(field.options ?? [], id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 160)
            }

        case .color:
            LabeledControl(label: field.label, help: field.help) {
                ColorPicker("", selection: Binding(
                    get: { Color(hex: stringBinding(field).wrappedValue) ?? .accentColor },
                    set: { stringBinding(field).wrappedValue = $0.hexString }
                ), supportsOpacity: false)
                .labelsHidden()
            }
        }
    }

    private func current(_ field: WidgetSettingField) -> JSONValue? {
        environment.widgetSetting(key: field.key, widgetID: descriptor.id)
    }

    private func boolBinding(_ field: WidgetSettingField) -> Binding<Bool> {
        Binding(
            get: { current(field)?.boolValue ?? field.defaultValue?.boolValue ?? false },
            set: { environment.setWidgetSetting(.bool($0), key: field.key, widgetID: descriptor.id) }
        )
    }

    private func stringBinding(_ field: WidgetSettingField) -> Binding<String> {
        Binding(
            get: { current(field)?.stringValue ?? field.defaultValue?.stringValue ?? "" },
            set: { environment.setWidgetSetting(.string($0), key: field.key, widgetID: descriptor.id) }
        )
    }

    private func doubleBinding(_ field: WidgetSettingField) -> Binding<Double> {
        Binding(
            get: { current(field)?.doubleValue ?? field.defaultValue?.doubleValue ?? field.minimum ?? 0 },
            set: { environment.setWidgetSetting(.number($0), key: field.key, widgetID: descriptor.id) }
        )
    }
}

/// Permission switches for a custom widget, with the risky ones called out.

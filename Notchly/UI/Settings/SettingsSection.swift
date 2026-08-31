import AppKit
import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 18)
    }
}

struct LabeledControl<Content: View>: View {
    let label: String
    var help: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12))
                if let help {
                    Text(help)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            content()
        }
    }
}

/// Slider with a live numeric readout — settings that change the panel's shape are much
/// easier to dial in when you can see the number.

struct ValueSlider: View {
    let label: String
    var help: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String = "pt"

    var body: some View {
        LabeledControl(label: label, help: help) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step).frame(width: 180)
                Text("\(Int(value.rounded()))\(unit)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .trailing)
            }
        }
    }
}

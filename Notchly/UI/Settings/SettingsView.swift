import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var selection: TabSelection
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                content
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 620, minHeight: 480)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Image(systemName: "rectangle.trailingthird.inset.filled")
                    .foregroundStyle(settings.settings.accentColor)
                Text("Notchly").font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selection.value = tab
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.symbol)
                            .frame(width: 16)
                            .foregroundStyle(selection.value == tab ? settings.settings.accentColor : .secondary)
                        Text(tab.label)
                            .font(.system(size: 12.5))
                            .foregroundStyle(selection.value == tab ? Color.primary : .secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selection.value == tab ? Color.primary.opacity(0.08) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            Spacer()
        }
        .frame(width: 168)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var content: some View {
        switch selection.value {
        case .general: GeneralSettingsPane()
        case .appearance: AppearanceSettingsPane()
        case .widgets: WidgetSettingsPane()
        case .custom: CustomWidgetPane()
        case .about: AboutPane()
        }
    }
}

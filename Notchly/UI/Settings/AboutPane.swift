import AppKit
import SwiftUI

struct AboutPane: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Notchly") {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.plateTop, Theme.plateBottom],
                                                 startPoint: .top, endPoint: .bottom))
                        NotchShape(edge: .trailing, cornerRadius: 8, inverseRadius: 4)
                            .fill(settings.settings.accentColor)
                            .frame(width: 22, height: 34)
                            .offset(x: 15)
                    }
                    .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Notchly").font(.system(size: 16, weight: .semibold))
                        Text("A notch-shaped panel that docks to any edge of your display.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }

            SettingsSection(title: "Shortcuts") {
                shortcut("Toggle the panel", HotKeyFormatter.describe(settings.settings.hotkey))
                shortcut("Close the panel", "⎋")
                shortcut("Search apps", "Type in the launcher field")
                shortcut("Launch highlighted app", "↩")
                shortcut("Pin a clipboard entry", "Right-click an entry")
            }

            SettingsSection(title: "Privacy",
                            footer: "Nothing leaves your Mac. Clipboard history is stored unencrypted in Application Support, so treat it like any other local file.") {
                bullet("Clipboard capture skips anything marked concealed by password managers.")
                bullet("Now Playing uses AppleScript, which macOS gates behind Automation permission.")
                bullet("Custom widgets are offline by default — network access is a per-widget switch.")
                bullet("Shell access is off unless you turn it on for a specific widget.")
            }
        }
    }

    private func shortcut(_ label: String, _ keys: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12))
            Spacer()
            Text(keys)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle().fill(.tertiary).frame(width: 4, height: 4).padding(.top, 6)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

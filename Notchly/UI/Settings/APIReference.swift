import AppKit
import SwiftUI

struct APIReference: View {
    private static let entries: [(String, String)] = [
        ("notchly.system.stats()", "CPU, memory, disk, network, battery, uptime"),
        ("notchly.system.info()", "Host, user, OS version, appearance"),
        ("notchly.storage.get/set/remove/keys/clear", "Per-widget key/value store, persisted"),
        ("notchly.settings.get(key) / .all()", "Values from your widget.json settings schema"),
        ("notchly.media.now() / playPause() / next() / previous()", "Now playing and transport"),
        ("notchly.clipboard.history(limit) / write(text)", "Clipboard history (needs permission)"),
        ("notchly.http.get(url) / .json(url)", "Network fetch proxy (needs permission)"),
        ("notchly.shell.run(command)", "Run a command (needs explicit approval)"),
        ("notchly.open(url)", "Open a link in the default browser"),
        ("notchly.notify(title, body)", "Post a notification"),
        ("notchly.ui.resize(h) / close() / holdOpen(b)", "Control the panel around you"),
        ("notchly.on('theme', cb)", "React to theme changes"),
        ("--notchly-accent, --notchly-text, …", "CSS variables injected into your page")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(Self.entries.enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .top, spacing: 10) {
                    Text(entry.0)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(width: 270, alignment: .leading)
                    Text(entry.1)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

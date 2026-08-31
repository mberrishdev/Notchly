import AppKit
import Combine

@MainActor
final class AppCatalog: ObservableObject {
    @Published private(set) var apps: [LaunchableApp] = []
    @Published private(set) var isIndexing = false

    private var iconCache: [String: NSImage] = [:]
    private var indexTask: Task<Void, Never>?

    private nonisolated static let searchRoots = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications"
    ]

    init() {}

    func refresh() {
        guard indexTask == nil else { return }
        isIndexing = true
        indexTask = Task { [weak self] in
            let found = await Self.scan()
            await MainActor.run {
                guard let self else { return }
                self.apps = found
                self.isIndexing = false
                self.indexTask = nil
            }
        }
    }

    private static func scan() async -> [LaunchableApp] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let manager = FileManager.default
                var results: [String: LaunchableApp] = [:]

                for root in searchRoots {
                    guard let entries = try? manager.contentsOfDirectory(atPath: root) else { continue }
                    for entry in entries where entry.hasSuffix(".app") {
                        let url = URL(fileURLWithPath: root).appendingPathComponent(entry)
                        let name = String(entry.dropLast(4))
                        let bundleID = Bundle(url: url)?.bundleIdentifier
                        let app = LaunchableApp(name: name, url: url, bundleID: bundleID)
                        results[app.id] = app
                    }
                }
                let sorted = results.values.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                continuation.resume(returning: sorted)
            }
        }
    }

    func icon(for app: LaunchableApp) -> NSImage {
        if let cached = iconCache[app.id] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: app.url.path)
        icon.size = NSSize(width: 48, height: 48)
        iconCache[app.id] = icon
        return icon
    }

    func launch(_ app: LaunchableApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)
    }

    func app(withID id: String) -> LaunchableApp? {
        apps.first { $0.id == id }
    }

    func search(_ query: String, limit: Int = 8) -> [LaunchableApp] {
        Self.rank(query, in: apps, limit: limit)
    }

    /// Subsequence match with a light relevance score: prefix beats word-start beats
    /// scattered match, so typing "saf" surfaces Safari rather than "Set Alarm Fast".
    nonisolated static func rank(_ query: String, in apps: [LaunchableApp], limit: Int = 8) -> [LaunchableApp] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        var scored: [(LaunchableApp, Int)] = []
        for app in apps {
            guard let score = score(needle: needle, app: app) else { continue }
            scored.append((app, score))
        }
        return scored
            .sorted { $0.1 == $1.1 ? $0.0.name.count < $1.0.name.count : $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    private nonisolated static func score(needle: String, app: LaunchableApp) -> Int? {
        let haystack = app.searchKey
        if haystack == needle { return 1000 }
        if haystack.hasPrefix(needle) { return 800 - haystack.count }
        if app.initials.hasPrefix(needle) { return 700 }
        if let range = haystack.range(of: needle) {
            let isWordStart = range.lowerBound == haystack.startIndex
                || haystack[haystack.index(before: range.lowerBound)] == " "
            return (isWordStart ? 600 : 400) - haystack.count
        }
        // Fall back to a scattered subsequence match.
        var index = haystack.startIndex
        for character in needle {
            guard let found = haystack[index...].firstIndex(of: character) else { return nil }
            index = haystack.index(after: found)
        }
        return 200 - haystack.count
    }
}

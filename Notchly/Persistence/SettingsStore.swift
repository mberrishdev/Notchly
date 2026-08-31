import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: NotchlySettings {
        didSet { guard settings != oldValue else { return }; scheduleSave() }
    }

    private var saveTask: Task<Void, Never>?
    private let url: URL

    static let shared = SettingsStore()

    private init() {
        url = AppPaths.supportDirectory.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(NotchlySettings.self, from: data) {
            settings = decoded
        } else {
            settings = NotchlySettings()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = settings
        saveTask = Task { [url] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await Self.write(snapshot, to: url)
        }
    }

    /// Flushes immediately — used on termination, where the debounce would lose the last edit.
    func saveNow() {
        saveTask?.cancel()
        let snapshot = settings
        let target = url
        Task.detached(priority: .userInitiated) { await Self.write(snapshot, to: target) }
    }

    private static func write(_ settings: NotchlySettings, to url: URL) async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func slot(for widgetID: String) -> WidgetSlot? {
        settings.slots.first { $0.widgetID == widgetID }
    }

    func preference(_ key: String, for widgetID: String) -> JSONValue? {
        slot(for: widgetID)?.preferences[key]
    }

    func setPreference(_ value: JSONValue?, key: String, for widgetID: String) {
        guard let index = settings.slots.firstIndex(where: { $0.widgetID == widgetID }) else { return }
        settings.slots[index].preferences[key] = value
    }
}

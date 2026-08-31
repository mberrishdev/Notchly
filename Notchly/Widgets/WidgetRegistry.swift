import SwiftUI

@MainActor
final class WidgetRegistry: ObservableObject {
    @Published private(set) var descriptors: [WidgetDescriptor] = []

    private unowned let environment: AppEnvironment

    /// Pure data, so it stays reachable without hopping to the main actor.
    nonisolated static let builtIn: [WidgetDescriptor] = [
        WidgetDescriptor(
            id: "clock", name: "Clock", summary: "Time, date and a second time zone.",
            symbol: "clock", kind: .builtIn,
            settingsSchema: [
                WidgetSettingField(key: "format", label: "Time format", kind: .select,
                                   help: nil, defaultValue: .string("24-hour"),
                                   options: ["24-hour", "12-hour"], minimum: nil, maximum: nil),
                WidgetSettingField(key: "showSeconds", label: "Show seconds", kind: .boolean,
                                   help: nil, defaultValue: .bool(false),
                                   options: nil, minimum: nil, maximum: nil),
                WidgetSettingField(key: "secondaryTimeZone", label: "Second time zone", kind: .string,
                                   help: "An IANA identifier such as Europe/Berlin. Leave blank to hide.",
                                   defaultValue: .string(""), options: nil, minimum: nil, maximum: nil)
            ]),
        WidgetDescriptor(
            id: "media", name: "Now Playing", summary: "Artwork and transport for Music and Spotify.",
            symbol: "play.circle", kind: .builtIn,
            settingsSchema: [
                WidgetSettingField(key: "showArtwork", label: "Show artwork", kind: .boolean,
                                   help: nil, defaultValue: .bool(true),
                                   options: nil, minimum: nil, maximum: nil)
            ]),
        WidgetDescriptor(
            id: "system", name: "System", summary: "CPU, memory, disk, network and battery.",
            symbol: "chart.bar.xaxis", kind: .builtIn,
            settingsSchema: [
                WidgetSettingField(key: "showDisk", label: "Show disk", kind: .boolean,
                                   help: nil, defaultValue: .bool(true), options: nil, minimum: nil, maximum: nil),
                WidgetSettingField(key: "showNetwork", label: "Show network", kind: .boolean,
                                   help: nil, defaultValue: .bool(true), options: nil, minimum: nil, maximum: nil),
                WidgetSettingField(key: "showBattery", label: "Show battery", kind: .boolean,
                                   help: nil, defaultValue: .bool(true), options: nil, minimum: nil, maximum: nil),
                WidgetSettingField(key: "showProcesses", label: "Show top processes", kind: .boolean,
                                   help: "Samples `ps` every five seconds while the panel is open.",
                                   defaultValue: .bool(true), options: nil, minimum: nil, maximum: nil)
            ]),
        WidgetDescriptor(
            id: "launcher", name: "Quick Launcher", summary: "Pinned apps and instant search.",
            symbol: "square.grid.2x2", kind: .builtIn,
            settingsSchema: [
                WidgetSettingField(key: "columns", label: "Columns", kind: .number,
                                   help: nil, defaultValue: .number(5),
                                   options: nil, minimum: 3, maximum: 6)
            ]),
        WidgetDescriptor(
            id: "clipboard", name: "Clipboard", summary: "Everything you have copied, searchable.",
            symbol: "doc.on.clipboard", kind: .builtIn,
            settingsSchema: [
                WidgetSettingField(key: "visibleCount", label: "Entries shown", kind: .number,
                                   help: nil, defaultValue: .number(6),
                                   options: nil, minimum: 3, maximum: 15)
            ])
    ]

    init(environment: AppEnvironment) {
        self.environment = environment
        rebuild()
    }

    func rebuild() {
        descriptors = Self.builtIn + environment.webWidgets.packages.map(\.descriptor)
    }

    func descriptor(for id: String) -> WidgetDescriptor? {
        descriptors.first { $0.id == id }
    }

    /// Slots the user has enabled, in order, skipping any whose widget has vanished.
    func activeSlots() -> [(slot: WidgetSlot, descriptor: WidgetDescriptor)] {
        environment.settings.settings.slots.compactMap { slot in
            guard slot.isEnabled, let descriptor = descriptor(for: slot.widgetID) else { return nil }
            return (slot, descriptor)
        }
    }

    /// Widgets that exist but aren't in the user's panel yet.
    func availableDescriptors() -> [WidgetDescriptor] {
        let used = Set(environment.settings.settings.slots.map(\.widgetID))
        return descriptors.filter { !used.contains($0.id) }
    }

    @ViewBuilder
    func view(for descriptor: WidgetDescriptor) -> some View {
        switch descriptor.kind {
        case .builtIn:
            switch descriptor.id {
            case "clock": ClockWidget()
            case "media": MediaWidget()
            case "system": SystemWidget()
            case "launcher": LauncherWidget()
            case "clipboard": ClipboardWidget()
            default: MissingWidgetView(name: descriptor.name)
            }
        case .web:
            if let package = environment.webWidgets.package(id: descriptor.id) {
                WebWidgetContainer(package: package)
            } else {
                MissingWidgetView(name: descriptor.name)
            }
        }
    }
}

import AppKit
import SwiftUI
import Combine

@MainActor
final class AppEnvironment: ObservableObject {
    let settings: SettingsStore
    let metrics = SystemMetrics()
    let media = MediaController()
    let catalog = AppCatalog()
    let webWidgets = WebWidgetStore()
    let clipboard: ClipboardService
    private(set) lazy var registry = WidgetRegistry(environment: self)

    /// Widget logs, surfaced in Settings so authors can debug without a console.
    @Published private(set) var widgetLogs: [String: [String]] = [:]
    @Published private(set) var isDarkAppearance = true
    /// Set by widgets that are mid-interaction (a focused field, an open menu) so the
    /// panel doesn't slide shut underneath them.
    @Published private(set) var holdOpenOwners: Set<String> = []

    var holdsPanelOpen: Bool { !holdOpenOwners.isEmpty }

    private var cancellables = Set<AnyCancellable>()
    private var appearanceObserver: NSKeyValueObservation?
    /// Ambient sampling is held open for as long as the Idle handle needs it, so these
    /// track what is currently subscribed rather than re-subscribing on every change.
    private var holdsAmbientMetrics = false
    private var holdsAmbientMedia = false

    init() {
        settings = SettingsStore.shared
        clipboard = ClipboardService(settings: settings)
    }

    func bootstrap() {
        // Subscribe before the first scan, which posts the change notification itself.
        NotificationCenter.default.publisher(for: .notchlyWidgetsChanged)
            .sink { [weak self] _ in self?.registry.rebuild() }
            .store(in: &cancellables)

        clipboard.start()
        catalog.refresh()
        webWidgets.start()
        refreshAppearance()
        updateAmbientSampling()

        settings.$settings
            .map(\.handleChips)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateAmbientSampling() }
            .store(in: &cancellables)

        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.refreshAppearance() }
        }

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .debounce(for: .seconds(3), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.catalog.refresh() }
            .store(in: &cancellables)
    }

    func shutdown() {
        settings.saveNow()
        clipboard.stop()
        webWidgets.stop()
        setAmbient(metrics: false, media: false)
    }

    private func refreshAppearance() {
        isDarkAppearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Sampling is refcounted. While the Panel is closed the only thing that can keep
    /// it running is an Idle handle chip that needs live numbers.
    func panelDidOpen() {
        metrics.subscribe(.live)
        media.subscribe(.live)
        if catalog.apps.isEmpty { catalog.refresh() }
    }

    func panelWillClose() {
        metrics.unsubscribe(.live)
        media.unsubscribe(.live)
        holdOpenOwners.removeAll()
    }

    /// Starts or stops the slow background polling the Idle handle depends on. Chips
    /// that read no system state — the clock, widget icons — cost nothing here.
    func updateAmbientSampling() {
        let chips = settings.settings.handleChips
        setAmbient(metrics: chips.contains { $0.needsMetrics },
                   media: chips.contains { $0.needsMedia })
    }

    private func setAmbient(metrics wantsMetrics: Bool, media wantsMedia: Bool) {
        if wantsMetrics != holdsAmbientMetrics {
            wantsMetrics ? metrics.subscribe(.ambient) : metrics.unsubscribe(.ambient)
            holdsAmbientMetrics = wantsMetrics
        }
        if wantsMedia != holdsAmbientMedia {
            wantsMedia ? media.subscribe(.ambient) : media.unsubscribe(.ambient)
            holdsAmbientMedia = wantsMedia
        }
    }

    func setHoldOpen(_ hold: Bool, owner: String) {
        if hold { holdOpenOwners.insert(owner) } else { holdOpenOwners.remove(owner) }
    }

    func isPermissionGranted(_ permission: WidgetPermission, for widgetID: String) -> Bool {
        guard let descriptor = registry.descriptor(for: widgetID) else { return false }
        guard descriptor.requestedPermissions.contains(permission) else { return false }
        guard permission.requiresExplicitGrant else { return true }
        return approvedWidgets(for: permission).contains(widgetID)
    }

    private func approvedWidgets(for permission: WidgetPermission) -> Set<String> {
        switch permission {
        case .shell: return settings.settings.shellApprovedWidgets
        case .network: return settings.settings.networkApprovedWidgets
        case .clipboard: return settings.settings.clipboardApprovedWidgets
        case .system, .notifications: return []
        }
    }

    func setPermission(_ permission: WidgetPermission, granted: Bool, for widgetID: String) {
        guard permission.requiresExplicitGrant else { return }
        var approved = approvedWidgets(for: permission)
        if granted { approved.insert(widgetID) } else { approved.remove(widgetID) }
        switch permission {
        case .shell: settings.settings.shellApprovedWidgets = approved
        case .network: settings.settings.networkApprovedWidgets = approved
        case .clipboard: settings.settings.clipboardApprovedWidgets = approved
        case .system, .notifications: return
        }
        webWidgets.bumpRevision(for: widgetID)
    }

    func widgetSettings(widgetID: String) -> [String: JSONValue] {
        var values: [String: JSONValue] = [:]
        if let schema = registry.descriptor(for: widgetID)?.settingsSchema {
            for field in schema {
                if let defaultValue = field.defaultValue { values[field.key] = defaultValue }
            }
        }
        if let stored = settings.slot(for: widgetID)?.preferences {
            values.merge(stored) { _, new in new }
        }
        return values
    }

    func widgetSetting(key: String, widgetID: String) -> JSONValue? {
        widgetSettings(widgetID: widgetID)[key]
    }

    func setWidgetSetting(_ value: JSONValue?, key: String, widgetID: String) {
        settings.setPreference(value, key: key, for: widgetID)
        webWidgets.bumpRevision(for: widgetID)
    }

    func systemStatsPayload() -> [String: Any] {
        [
            "cpu": ["user": metrics.cpu.user, "system": metrics.cpu.system,
                    "idle": metrics.cpu.idle, "total": metrics.cpu.total],
            "memory": ["used": Double(metrics.memory.used), "total": Double(metrics.memory.total),
                       "fraction": metrics.memory.fraction, "pressure": metrics.memory.pressure],
            "disk": ["free": Double(metrics.disk.free), "total": Double(metrics.disk.total),
                     "fraction": metrics.disk.fraction],
            "network": ["down": metrics.network.downBytesPerSecond, "up": metrics.network.upBytesPerSecond],
            "battery": ["present": metrics.battery.isPresent, "level": metrics.battery.percentage,
                        "charging": metrics.battery.isCharging, "pluggedIn": metrics.battery.isPluggedIn,
                        "minutesRemaining": metrics.battery.minutesRemaining as Any],
            "uptime": metrics.uptime
        ]
    }

    func mediaPayload() -> [String: Any] {
        guard let track = media.nowPlaying else { return ["playing": false] as [String: Any] }
        return [
            "playing": track.isPlaying,
            "title": track.title,
            "artist": track.artist,
            "album": track.album,
            "duration": track.duration,
            "position": track.position,
            "app": track.app.rawValue
        ]
    }

    func themePayload() -> [String: String] {
        [
            "accent": settings.settings.accentHex,
            "text": "rgba(255,255,255,0.92)",
            "text-secondary": "rgba(255,255,255,0.56)",
            "text-tertiary": "rgba(255,255,255,0.34)",
            "surface": "rgba(255,255,255,0.06)",
            "surface-hover": "rgba(255,255,255,0.10)",
            "hairline": "rgba(255,255,255,0.10)",
            "radius": "12px",
            "appearance": isDarkAppearance ? "dark" : "light",
            "font": "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif"
        ]
    }

    func themeJSON() -> String {
        let payload = themePayload()
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    func appendWidgetLog(widgetID: String, line: String) {
        let stamp = Self.logFormatter.string(from: Date())
        var lines = widgetLogs[widgetID] ?? []
        lines.append("\(stamp)  \(line)")
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }
        widgetLogs[widgetID] = lines
    }

    func clearWidgetLog(widgetID: String) {
        widgetLogs[widgetID] = []
    }

    private static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

import Foundation
import SwiftUI

struct NotchlySettings: Codable, Hashable, Sendable {
    var edge: ScreenEdge = .trailing
    /// Where the panel sits along its edge: 0 is top/left, 1 is bottom/right.
    var alignment: Double = 0.42
    var panelWidth: Double = 372
    var panelHeight: Double = 540
    var handleThickness: Double = 5
    var handleLength: Double = 108
    /// What the handle shows while the panel is closed. Empty means the plain line.
    /// The clock alone is the default because it needs no sampling and triggers no
    /// permission prompts; the chips that do are opt-in.
    var handleChips: [IdleChip] = [.clock]
    /// How far the handle protrudes once it has chips to show.
    var handleContentThickness: Double = 30
    var cornerRadius: Double = 26
    var edgeInset: Double = 0

    var activation: ActivationMode = .hover
    var openDelay: Double = 0.14
    var closeDelay: Double = 0.42
    var isPinned: Bool = false
    var closeOnOutsideClick: Bool = true

    var material: PanelMaterial = .glass
    var opacity: Double = 0.96
    var accentHex: String = NotchlySettings.defaultAccentHex
    var showsHandleWhenIdle: Bool = true
    var reduceMotion: Bool = false

    var launchAtLogin: Bool = false
    var showsMenuBarIcon: Bool = true
    var hotkey: HotkeySpec = .default
    /// Persisted display identifier; nil follows the screen with the pointer.
    var preferredScreenID: Int?

    var slots: [WidgetSlot] = NotchlySettings.defaultSlots
    /// Web widget ids the user has explicitly allowed to run shell commands.
    var shellApprovedWidgets: Set<String> = []
    /// Web widget ids allowed to reach the network.
    var networkApprovedWidgets: Set<String> = []
    /// Web widget ids allowed to read clipboard history.
    var clipboardApprovedWidgets: Set<String> = []

    var clipboardHistoryLimit: Int = 120
    var clipboardCapturesImages: Bool = true
    var hasCompletedFirstRun: Bool = false
    /// Opens Safari's inspector on custom widgets, for people authoring them.
    var enableWebInspector: Bool = false

    init() {}

    /// Decoded field by field against a fresh set of defaults.
    ///
    /// The synthesized initializer treats every property as required, so a
    /// `settings.json` written by an older build — one predating a property added since
    /// — would fail to decode and silently reset every preference the user has. Falling
    /// back per key means a new setting simply arrives at its default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = NotchlySettings()
        edge = container.value(.edge, defaults.edge)
        alignment = container.value(.alignment, defaults.alignment)
        panelWidth = container.value(.panelWidth, defaults.panelWidth)
        panelHeight = container.value(.panelHeight, defaults.panelHeight)
        handleThickness = container.value(.handleThickness, defaults.handleThickness)
        handleLength = container.value(.handleLength, defaults.handleLength)
        handleChips = container.value(.handleChips, defaults.handleChips)
        handleContentThickness = container.value(.handleContentThickness, defaults.handleContentThickness)
        cornerRadius = container.value(.cornerRadius, defaults.cornerRadius)
        edgeInset = container.value(.edgeInset, defaults.edgeInset)
        activation = container.value(.activation, defaults.activation)
        openDelay = container.value(.openDelay, defaults.openDelay)
        closeDelay = container.value(.closeDelay, defaults.closeDelay)
        isPinned = container.value(.isPinned, defaults.isPinned)
        closeOnOutsideClick = container.value(.closeOnOutsideClick, defaults.closeOnOutsideClick)
        material = container.value(.material, defaults.material)
        opacity = container.value(.opacity, defaults.opacity)
        accentHex = container.value(.accentHex, defaults.accentHex)
        showsHandleWhenIdle = container.value(.showsHandleWhenIdle, defaults.showsHandleWhenIdle)
        reduceMotion = container.value(.reduceMotion, defaults.reduceMotion)
        launchAtLogin = container.value(.launchAtLogin, defaults.launchAtLogin)
        showsMenuBarIcon = container.value(.showsMenuBarIcon, defaults.showsMenuBarIcon)
        hotkey = container.value(.hotkey, defaults.hotkey)
        preferredScreenID = try container.decodeIfPresent(Int.self, forKey: .preferredScreenID)
        slots = container.value(.slots, defaults.slots)
        shellApprovedWidgets = container.value(.shellApprovedWidgets, defaults.shellApprovedWidgets)
        networkApprovedWidgets = container.value(.networkApprovedWidgets, defaults.networkApprovedWidgets)
        clipboardApprovedWidgets = container.value(.clipboardApprovedWidgets, defaults.clipboardApprovedWidgets)
        clipboardHistoryLimit = container.value(.clipboardHistoryLimit, defaults.clipboardHistoryLimit)
        clipboardCapturesImages = container.value(.clipboardCapturesImages, defaults.clipboardCapturesImages)
        hasCompletedFirstRun = container.value(.hasCompletedFirstRun, defaults.hasCompletedFirstRun)
        enableWebInspector = container.value(.enableWebInspector, defaults.enableWebInspector)
    }

    static let defaultSlots: [WidgetSlot] = [
        WidgetSlot(kind: .builtIn, widgetID: "clock"),
        WidgetSlot(kind: .builtIn, widgetID: "media"),
        WidgetSlot(kind: .builtIn, widgetID: "system"),
        WidgetSlot(kind: .builtIn, widgetID: "launcher"),
        WidgetSlot(kind: .builtIn, widgetID: "clipboard")
    ]

    static let defaultAccentHex = "#6E9BFF"

    var accentColor: Color { Color(hex: accentHex) ?? Color(sRGB: 0x6E9BFF) }
}

/// Owns the on-disk settings file. Writes are coalesced so that dragging a slider
/// doesn't turn into a few hundred file writes.

private extension KeyedDecodingContainer {
    /// Decodes a value, falling back when the key is absent *or* holds something this
    /// build can no longer make sense of, such as a renamed enum case.
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        // `try?` flattens the double optional, so a missing key, a null, and a value
        // this build can no longer decode all arrive here as nil — which is exactly the
        // set of cases that should fall back.
        guard let decoded = try? decodeIfPresent(T.self, forKey: key) else { return fallback }
        return decoded
    }
}

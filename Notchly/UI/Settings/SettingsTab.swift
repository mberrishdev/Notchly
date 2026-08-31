import Foundation
import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, widgets, custom, about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .widgets: return "Widgets"
        case .custom: return "Custom Widgets"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .widgets: return "square.grid.2x2"
        case .custom: return "curlybraces"
        case .about: return "info.circle"
        }
    }
}

/// A plain AppKit window rather than a SwiftUI `Settings` scene, because the app runs
/// as an accessory with no main menu to hang a Settings item off.

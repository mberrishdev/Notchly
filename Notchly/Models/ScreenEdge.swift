import Foundation
import SwiftUI

enum ScreenEdge: String, Codable, CaseIterable, Identifiable, Sendable {
    case top, bottom, leading, trailing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .leading: return "Left"
        case .trailing: return "Right"
        }
    }

    var symbol: String {
        switch self {
        case .top: return "rectangle.topthird.inset.filled"
        case .bottom: return "rectangle.bottomthird.inset.filled"
        case .leading: return "rectangle.leadingthird.inset.filled"
        case .trailing: return "rectangle.trailingthird.inset.filled"
        }
    }

    /// True for the left and right edges, where the panel extends horizontally into
    /// the display. Note this describes the panel's growth direction, not the
    /// orientation of the edge itself.
    var growsHorizontally: Bool { self == .leading || self == .trailing }
}

enum ActivationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case hover, click, hotkeyOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hover: return "Hover"
        case .click: return "Click"
        case .hotkeyOnly: return "Hotkey only"
        }
    }

    var detail: String {
        switch self {
        case .hover: return "Opens when the pointer rests on the handle."
        case .click: return "Opens on click, so the handle never opens by accident."
        case .hotkeyOnly: return "Stays closed until the keyboard shortcut fires."
        }
    }
}

enum PanelMaterial: String, Codable, CaseIterable, Identifiable, Sendable {
    case glass, tinted, solid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .glass: return "Glass"
        case .tinted: return "Tinted"
        case .solid: return "Solid"
        }
    }
}

/// One entry in the user's panel. `kind` distinguishes a compiled-in widget from a
/// folder the user dropped into the widgets directory.

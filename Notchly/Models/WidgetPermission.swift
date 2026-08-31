import Foundation
import SwiftUI

enum WidgetPermission: String, Codable, Hashable, CaseIterable, Sendable {
    case network, shell, system, clipboard, notifications

    var label: String {
        switch self {
        case .network: return "Network access"
        case .shell: return "Run shell commands"
        case .system: return "Read system stats"
        case .clipboard: return "Read clipboard history"
        case .notifications: return "Post notifications"
        }
    }

    var detail: String {
        switch self {
        case .network: return "Lets the widget load remote pages and call APIs."
        case .shell: return "Lets the widget run commands as you. Only grant this to widgets you trust."
        case .system: return "CPU, memory, disk, network and battery readings."
        case .clipboard: return "The text and links you have copied recently."
        case .notifications: return "Banners in Notification Center."
        }
    }

    /// Permissions the user must approve by hand; the rest are granted as soon as the
    /// manifest declares them. This is the only place that list lives — enforcement,
    /// the settings toggles, and the widget's own lock badge all read it.
    var requiresExplicitGrant: Bool {
        switch self {
        case .shell, .clipboard, .network: return true
        case .system, .notifications: return false
        }
    }

    var symbol: String {
        switch self {
        case .network: return "network"
        case .shell: return "terminal"
        case .system: return "cpu"
        case .clipboard: return "doc.on.clipboard"
        case .notifications: return "bell"
        }
    }
}

/// A preference a widget declares so Notchly can render a native control for it.

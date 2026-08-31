import Foundation
import AppKit

extension Notification.Name {
    static let notchlyRequestClose = Notification.Name("notchly.requestClose")
    static let notchlyRequestOpen = Notification.Name("notchly.requestOpen")
    static let notchlyWidgetsChanged = Notification.Name("notchly.widgetsChanged")
}

/// Hosts the SwiftUI tree and reports pointer enter/exit for the whole window.

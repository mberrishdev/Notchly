import Foundation
import SwiftUI

struct WidgetSlot: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case builtIn, web }

    var id: UUID
    var kind: Kind
    /// `ClockWidget.identifier` for built-ins, the manifest id for web widgets.
    var widgetID: String
    var isEnabled: Bool
    var preferences: [String: JSONValue]

    init(id: UUID = UUID(), kind: Kind, widgetID: String, isEnabled: Bool = true, preferences: [String: JSONValue] = [:]) {
        self.id = id
        self.kind = kind
        self.widgetID = widgetID
        self.isEnabled = isEnabled
        self.preferences = preferences
    }
}

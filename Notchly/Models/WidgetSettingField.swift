import Foundation
import SwiftUI

struct WidgetSettingField: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case string, number, boolean, select, color
    }

    var key: String
    var label: String
    var kind: Kind
    var help: String?
    var defaultValue: JSONValue?
    var options: [String]?
    var minimum: Double?
    var maximum: Double?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, help, options, minimum, maximum
        case kind = "type"
        case defaultValue = "default"
    }
}

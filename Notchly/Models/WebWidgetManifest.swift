import Foundation
import SwiftUI

struct WebWidgetManifest: Codable, Hashable {
    var id: String
    var name: String
    var version: String?
    var author: String?
    var description: String?
    var entry: String?
    var icon: String?
    var height: Double?
    var minHeight: Double?
    var maxHeight: Double?
    var permissions: [WidgetPermission]?
    /// Seconds between automatic reloads; 0 or absent means never.
    var refreshInterval: Double?
    var settings: [WidgetSettingField]?
    var entryFile: String { entry ?? "index.html" }
}

import SwiftUI

struct WidgetDescriptor: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var summary: String
    var symbol: String
    var kind: WidgetSlot.Kind
    var author: String?
    var version: String?
    var folderURL: URL?
    var settingsSchema: [WidgetSettingField]
    /// Height the widget wants when it can't size itself (web widgets).
    var preferredHeight: CGFloat?
    var requestedPermissions: Set<WidgetPermission>
    var loadError: String?

    init(id: String, name: String, summary: String, symbol: String, kind: WidgetSlot.Kind,
                author: String? = nil, version: String? = nil, folderURL: URL? = nil,
                settingsSchema: [WidgetSettingField] = [], preferredHeight: CGFloat? = nil,
                requestedPermissions: Set<WidgetPermission> = [], loadError: String? = nil) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbol = symbol
        self.kind = kind
        self.author = author
        self.version = version
        self.folderURL = folderURL
        self.settingsSchema = settingsSchema
        self.preferredHeight = preferredHeight
        self.requestedPermissions = requestedPermissions
        self.loadError = loadError
    }
}

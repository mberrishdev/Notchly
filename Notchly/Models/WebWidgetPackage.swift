import Foundation
import SwiftUI

struct WebWidgetPackage: Identifiable, Hashable {
    var manifest: WebWidgetManifest
    var folderURL: URL
    /// Bumped whenever files change on disk, which forces the web view to reload.
    var revision: Int

    var id: String { manifest.id }
    var entryURL: URL { folderURL.appendingPathComponent(manifest.entryFile) }

    var descriptor: WidgetDescriptor {
        WidgetDescriptor(id: manifest.id,
                         name: manifest.name,
                         summary: manifest.description ?? "Custom widget",
                         symbol: manifest.icon ?? "square.grid.2x2",
                         kind: .web,
                         author: manifest.author,
                         version: manifest.version,
                         folderURL: folderURL,
                         settingsSchema: manifest.settings ?? [],
                         preferredHeight: manifest.height.map { CGFloat($0) } ?? 160,
                         requestedPermissions: Set(manifest.permissions ?? []))
    }
}

/// A folder that looked like a widget but couldn't be loaded — surfaced in Settings so
/// the failure is visible rather than silent.

struct WebWidgetLoadFailure: Identifiable, Hashable {
    var id: String { folderURL.path }
    var folderURL: URL
    var reason: String
}

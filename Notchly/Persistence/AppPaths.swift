import Foundation

enum AppPaths {
    static let bundleIdentifier = "com.notchly.Notchly"

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Notchly", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Where users drop custom widget folders. Kept deliberately shallow and obvious.
    static var widgetsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("Widgets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var widgetStorageDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("WidgetStorage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var clipboardStore: URL {
        supportDirectory.appendingPathComponent("clipboard.json")
    }

    static var clipboardImagesDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("ClipboardImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

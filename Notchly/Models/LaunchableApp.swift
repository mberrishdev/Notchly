import Foundation
import AppKit
import Combine

struct LaunchableApp: Identifiable, Hashable, Sendable {
    var id: String { bundleID ?? url.path }
    var name: String
    var url: URL
    var bundleID: String?
    /// Lowercased name plus initials, precomputed so search stays allocation-free.
    var searchKey: String
    var initials: String
}

/// Indexes installed applications for the launcher widget and ranks them for search.

extension LaunchableApp {
    /// Builds the precomputed search fields alongside the app, so ranking never has to
    /// lowercase or re-derive initials while the user is typing.
    init(name: String, url: URL, bundleID: String?) {
        self.init(name: name,
                  url: url,
                  bundleID: bundleID,
                  searchKey: name.lowercased(),
                  initials: name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
                      .compactMap(\.first)
                      .map(String.init)
                      .joined()
                      .lowercased())
    }
}

import Foundation
import AppKit
import Combine
import CryptoKit

struct ClipboardItem: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case text, url, image, file, color }

    var id: UUID
    var kind: Kind
    var text: String
    var imageFile: String?
    var createdAt: Date
    var sourceBundleID: String?
    var sourceName: String?
    var isPinned: Bool
    /// Digest of the payload, used to collapse repeat copies of the same thing.
    var fingerprint: String

    var preview: String {
        switch kind {
        case .image: return "Image"
        default:
            let collapsed = text.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return collapsed.isEmpty ? "(whitespace)" : collapsed
        }
    }

    var lineCount: Int { text.split(separator: "\n", omittingEmptySubsequences: false).count }
}

/// Watches the general pasteboard and keeps a searchable, persisted history.

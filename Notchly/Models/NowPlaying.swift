import Foundation
import AppKit
import Combine

struct NowPlaying: Equatable, Sendable {
    var app: MediaController.Player
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var duration: Double
    var position: Double
    var artworkKey: String?

    var progress: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
}

/// Drives whatever is playing audio.
///
/// Now-playing metadata comes from AppleScript, which needs no private frameworks and
/// asks the user for Automation access the normal way. Transport control falls back to
/// synthesised media keys so players we can't script (browsers, video apps) still respond.

import Foundation
import SwiftUI

struct HotkeySpec: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    var isEnabled: Bool

    /// ⌥⌘N — deliberately not a common shortcut in other apps.
    static let `default` = HotkeySpec(keyCode: 45, modifiers: 0x0800 | 0x0100, isEnabled: true)

    init(keyCode: UInt32, modifiers: UInt32, isEnabled: Bool) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isEnabled = isEnabled
    }
}

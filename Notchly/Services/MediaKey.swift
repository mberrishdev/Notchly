import AppKit
import Combine

enum MediaKey {
    static func post(_ key: Int32) {
        for isDown in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: UInt(isDown ? 0xA00 : 0xB00))
            let data1 = Int((key << 16) | (isDown ? 0xA00 : 0xB00))
            guard let event = NSEvent.otherEvent(with: .systemDefined,
                                                 location: .zero,
                                                 modifierFlags: flags,
                                                 timestamp: 0,
                                                 windowNumber: 0,
                                                 context: nil,
                                                 subtype: 8,
                                                 data1: data1,
                                                 data2: -1) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    static var isAvailable: Bool { AXIsProcessTrusted() }
}

/// HID usage codes for the media transport keys, from IOKit's `ev_keymap.h`.
let NX_KEYTYPE_PLAY: Int32 = 16
let NX_KEYTYPE_NEXT: Int32 = 17
let NX_KEYTYPE_PREVIOUS: Int32 = 18

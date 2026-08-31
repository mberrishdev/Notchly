import AppKit
import Carbon.HIToolbox

enum HotKeyFormatter {
    static func describe(_ spec: HotkeySpec) -> String {
        guard spec.isEnabled, spec.keyCode != 0 else { return "None" }
        var text = ""
        if spec.modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if spec.modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if spec.modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if spec.modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyName(spec.keyCode)
    }

    static func keyName(_ keyCode: UInt32) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(keyCode)"
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let result = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, 4, &length, &characters)
        }
        guard result == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }

    /// Carbon modifier mask from an AppKit event.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    private static let specialKeys: [Int: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]
}

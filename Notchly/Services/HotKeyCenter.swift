import AppKit
import Carbon.HIToolbox

@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onFire: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x4E544348 // 'NTCH'

    private init() {}

    func apply(_ spec: HotkeySpec) {
        unregister()
        guard spec.isEnabled, spec.keyCode != 0 else { return }
        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(spec.keyCode, spec.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { hotKeyRef = nil }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { HotKeyCenter.shared.onFire?() }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}

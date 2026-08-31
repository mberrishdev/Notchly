import AppKit

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isFloatingPanel = true
        // The panel is an accessory surface; it should never appear in window lists.
        isExcludedFromWindowsMenu = true
        acceptsMouseMovedEvents = true
    }

    /// Escape closes the panel rather than beeping.
    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: .notchlyRequestClose, object: nil)
    }
}

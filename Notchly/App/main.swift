import AppKit

// Notchly is an accessory app: no Dock tile, no menu bar of its own, just the panel
// and a status item. Building the application object by hand rather than through the
// SwiftUI App lifecycle keeps full control over window levels and activation, both of
// which a floating non-activating panel depends on.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let selectedTab = TabSelection()

    func show(environment: AppEnvironment, tab: SettingsTab? = nil) {
        if let tab { selectedTab.value = tab }

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = SettingsView(selection: selectedTab)
            .environmentObject(environment)
            .environmentObject(environment.settings)
            .environmentObject(environment.registry)
            .environmentObject(environment.webWidgets)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Notchly Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
        window.setContentSize(NSSize(width: 660, height: 560))
        window.minSize = NSSize(width: 620, height: 480)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .normal
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

/// Shared selection so `show(tab:)` can jump to a tab before the view exists.

@MainActor
final class TabSelection: ObservableObject {
    @Published var value: SettingsTab = .general
}

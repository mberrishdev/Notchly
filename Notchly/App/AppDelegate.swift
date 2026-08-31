import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment!
    private var panelController: PanelController!
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment = AppEnvironment()
        environment.bootstrap()
        panelController = PanelController(environment: environment)

        HotKeyCenter.shared.onFire = { [weak self] in self?.panelController.toggle() }
        HotKeyCenter.shared.apply(environment.settings.settings.hotkey)

        environment.settings.$settings
            .map(\.hotkey)
            .removeDuplicates()
            .sink { HotKeyCenter.shared.apply($0) }
            .store(in: &cancellables)

        environment.settings.$settings
            .map(\.showsMenuBarIcon)
            .removeDuplicates()
            .sink { [weak self] shows in self?.setStatusItem(visible: shows) }
            .store(in: &cancellables)

        setStatusItem(visible: environment.settings.settings.showsMenuBarIcon)

        if !environment.settings.settings.hasCompletedFirstRun {
            environment.settings.settings.hasCompletedFirstRun = true
            // Give the user something to look at rather than an invisible sliver.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                self.panelController.open(focus: true)
                SettingsWindowController.shared.show(environment: self.environment, tab: .general)
            }
        }

        if environment.settings.settings.isPinned {
            panelController.open(focus: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.shutdown()
        HotKeyCenter.shared.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController.open(focus: true)
        return true
    }

    private func setStatusItem(visible: Bool) {
        guard visible else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.trailingthird.inset.filled",
                                     accessibilityDescription: "Notchly")
        item.button?.image?.isTemplate = true
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let toggle = NSMenuItem(title: "Show Panel", action: #selector(togglePanel), keyEquivalent: "")
        toggle.target = self
        toggle.tag = MenuTag.toggle
        menu.addItem(toggle)

        let pin = NSMenuItem(title: "Keep Panel Open", action: #selector(togglePin), keyEquivalent: "")
        pin.target = self
        pin.tag = MenuTag.pin
        pin.state = environment.settings.settings.isPinned ? .on : .off
        menu.addItem(pin)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.tag = MenuTag.login
        menu.addItem(login)

        menu.addItem(.separator())

        for edge in ScreenEdge.allCases {
            let item = NSMenuItem(title: "Dock \(edge.label)", action: #selector(setEdge(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = edge.rawValue
            item.state = environment.settings.settings.edge == edge ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let widgets = NSMenuItem(title: "Open Widgets Folder", action: #selector(openWidgets), keyEquivalent: "")
        widgets.target = self
        menu.addItem(widgets)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Notchly", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.delegate = MenuRefresher.shared
        MenuRefresher.shared.onOpen = { [weak self] menu in self?.refresh(menu) }
        return menu
    }

    private func refresh(_ menu: NSMenu) {
        menu.item(withTag: MenuTag.toggle)?.title = panelController.isExpanded ? "Hide Panel" : "Show Panel"
        menu.item(withTag: MenuTag.pin)?.state = environment.settings.settings.isPinned ? .on : .off
        menu.item(withTag: MenuTag.login)?.state = LoginItem.isEnabled ? .on : .off
        for item in menu.items {
            guard let raw = item.representedObject as? String else { continue }
            item.state = environment.settings.settings.edge.rawValue == raw ? .on : .off
        }
    }

    private enum MenuTag {
        static let toggle = 1
        static let pin = 2
        static let login = 3
    }

    @objc private func togglePanel() { panelController.toggle() }
    @objc private func togglePin() { panelController.togglePinned() }

    @objc private func toggleLoginItem() {
        let error = LoginItem.set(!LoginItem.isEnabled)
        // Read the real state back rather than assuming the change took.
        environment.settings.settings.launchAtLogin = LoginItem.isEnabled
        guard let error else { return }
        let alert = NSAlert()
        alert.messageText = "Notchly couldn't change its login item"
        alert.informativeText = error
        alert.alertStyle = .warning
        alert.runModal()
    }
    @objc private func openWidgets() { environment.webWidgets.revealInFinder() }
    @objc private func openSettings() { SettingsWindowController.shared.show(environment: environment) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func setEdge(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let edge = ScreenEdge(rawValue: raw) else { return }
        environment.settings.settings.edge = edge
    }
}

/// Small shim so the status menu can refresh its checkmarks right before it opens.

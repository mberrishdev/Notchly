import AppKit
import SwiftUI
import Combine

@MainActor
final class PanelController: NSObject, ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var isHandleHighlighted = false
    @Published private(set) var isDragging = false
    @Published private(set) var geometry: PanelGeometry

    private var panel: NotchPanel!
    private var container: TrackingContainerView!
    private let settingsStore: SettingsStore
    private let environment: AppEnvironment

    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var frameTask: Task<Void, Never>?
    private var pointerWatchdog: Timer?
    private var outsideClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    /// Guards against the panel re-opening under a pointer that never left the handle
    /// after an explicit close.
    private var hoverSuppressedUntil = Date.distantPast

    init(environment: AppEnvironment) {
        self.environment = environment
        self.settingsStore = environment.settings
        let screen = Self.resolveScreen(settings: environment.settings.settings)
        self.geometry = PanelGeometry(settings: environment.settings.settings, screen: screen)
        super.init()
        // The widget count is only reachable once `self` exists, and the handle sizes
        // from it, so settle the geometry before the window is built from it.
        geometry = makeGeometry()
        buildWindow()
        observe()
    }

    private func buildWindow() {
        let frame = geometry.windowFrame(expanded: false)
        panel = NotchPanel(contentRect: frame)

        container = TrackingContainerView(frame: CGRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]
        container.onMouseEntered = { [weak self] in self?.pointerEntered() }
        container.onMouseExited = { [weak self] in self?.pointerExited() }
        container.onMouseDown = { [weak self] in self?.contentClicked() }

        let root = PanelRootView()
            .environmentObject(self)
            .environmentObject(settingsStore)
            .environmentObject(environment)
            // Each service publishes its own changes; nested ObservableObjects don't
            // propagate through AppEnvironment, so they are injected individually.
            .environmentObject(environment.metrics)
            .environmentObject(environment.media)
            .environmentObject(environment.clipboard)
            .environmentObject(environment.catalog)
            .environmentObject(environment.registry)
        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = []
        container.addSubview(hosting)

        panel.contentView = container
        panel.orderFrontRegardless()
    }

    private func observe() {
        settingsStore.$settings
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in self?.settingsChanged(settings) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .notchlyWidgetsChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshGeometry() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .notchlyRequestClose)
            .sink { [weak self] _ in self?.close(immediate: false) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .notchlyRequestOpen)
            .sink { [weak self] _ in self?.open(focus: true) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refreshGeometry() }
            .store(in: &cancellables)
    }

    private func settingsChanged(_ settings: NotchlySettings) {
        refreshGeometry()
        if settings.isPinned && !isExpanded {
            open(focus: false)
        } else if !settings.isPinned && isExpanded && !isPointerInsidePanel() {
            scheduleClose()
        }
    }

    private static func resolveScreen(settings: NotchlySettings) -> NSScreen {
        if let id = settings.preferredScreenID,
           let match = NSScreen.screens.first(where: { $0.notchlyDisplayID == id }) {
            return match
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    func refreshGeometry() {
        geometry = makeGeometry()
        applyFrame(expanded: isExpanded)
    }

    private func makeGeometry() -> PanelGeometry {
        PanelGeometry(settings: settingsStore.settings,
                      screen: Self.resolveScreen(settings: settingsStore.settings),
                      enabledWidgetCount: environment.registry.activeSlots().count)
    }

    private func applyFrame(expanded: Bool) {
        let target = geometry.windowFrame(expanded: expanded)
        guard panel.frame != target else { return }
        panel.setFrame(target, display: true, animate: false)
    }

    func open(focus: Bool) {
        openTask?.cancel(); openTask = nil
        closeTask?.cancel(); closeTask = nil
        guard !isExpanded else {
            if focus { focusPanel() }
            return
        }

        refreshGeometryForOpen()
        // Grow the (transparent) window first so the animation has room to play out.
        applyFrame(expanded: true)
        panel.orderFrontRegardless()

        withAnimation(Theme.openSpring(reduced: settingsStore.settings.reduceMotion)) {
            isExpanded = true
            isHandleHighlighted = false
        }
        if focus { focusPanel() }
        startPointerWatchdog()
        startOutsideClickMonitor()
        environment.panelDidOpen()
    }

    /// Only re-target the display when the panel is closed; moving it mid-session is jarring.
    private func refreshGeometryForOpen() {
        geometry = makeGeometry()
    }

    func close(immediate: Bool) {
        openTask?.cancel(); openTask = nil
        closeTask?.cancel(); closeTask = nil
        guard isExpanded else { return }
        if settingsStore.settings.isPinned && !immediate { return }

        hoverSuppressedUntil = Date().addingTimeInterval(0.45)
        stopPointerWatchdog()
        stopOutsideClickMonitor()
        environment.panelWillClose()

        withAnimation(Theme.closeSpring(reduced: settingsStore.settings.reduceMotion)) {
            isExpanded = false
            isHandleHighlighted = false
        }
        panel.resignKey()

        frameTask?.cancel()
        frameTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(immediate ? 10 : 340))
            guard let self, !Task.isCancelled, !self.isExpanded else { return }
            self.applyFrame(expanded: false)
        }
    }

    func toggle() {
        if isExpanded { close(immediate: true) } else { open(focus: true) }
    }

    func togglePinned() {
        settingsStore.settings.isPinned.toggle()
        if settingsStore.settings.isPinned { open(focus: false) }
    }

    private func focusPanel() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func pointerEntered() {
        guard !isDragging else { return }
        guard !isExpanded else {
            closeTask?.cancel(); closeTask = nil
            return
        }
        guard Date() >= hoverSuppressedUntil else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isHandleHighlighted = true }
        guard settingsStore.settings.activation == .hover else { return }

        openTask?.cancel()
        let delay = settingsStore.settings.openDelay
        openTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            guard self.isPointerInsidePanel() else { return }
            self.open(focus: false)
        }
    }

    private func pointerExited() {
        guard !isDragging else { return }
        openTask?.cancel(); openTask = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isHandleHighlighted = false }
        if isExpanded { scheduleClose() }
    }

    private func scheduleClose() {
        guard !settingsStore.settings.isPinned, !isDragging else { return }
        closeTask?.cancel()
        let delay = settingsStore.settings.closeDelay
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.isExpanded else { return }
            guard !self.isPointerInsidePanel() else { return }
            guard !self.environment.holdsPanelOpen else { return }
            self.close(immediate: false)
        }
    }

    /// A click that wasn't a drag. The drag gesture decides which it was, so the panel
    /// can be dragged off its handle without popping open on the way.
    func handleTapped() {
        guard settingsStore.settings.activation != .hotkeyOnly else { return }
        if isExpanded { focusPanel() } else { open(focus: true) }
    }

    private func contentClicked() {
        guard isExpanded else { return }
        focusPanel()
    }

    /// Repositioning by dragging the panel itself, which is far more direct than
    /// hunting for the edge and alignment controls in Settings.
    func beginDrag() {
        openTask?.cancel(); openTask = nil
        closeTask?.cancel(); closeTask = nil
        isDragging = true
        environment.setHoldOpen(true, owner: "drag")
    }

    /// Called on every drag change. The pointer's absolute position drives the panel
    /// rather than an accumulated translation, so the panel can't drift away from the
    /// cursor as the window moves underneath it.
    func dragToPointer() {
        guard isDragging else { return }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
                ?? NSScreen.main else { return }
        guard let placement = PanelPlacement.resolve(pointer: pointer, in: screen.frame) else { return }

        settingsStore.settings.edge = placement.edge
        settingsStore.settings.alignment = placement.alignment
        // Only re-pin the display if the user had pinned one; otherwise leave the
        // panel following the pointer as they configured.
        if settingsStore.settings.preferredScreenID != nil, let id = screen.notchlyDisplayID {
            settingsStore.settings.preferredScreenID = id
        }
    }

    func endDrag() {
        guard isDragging else { return }
        isDragging = false
        environment.setHoldOpen(false, owner: "drag")
        hoverSuppressedUntil = Date().addingTimeInterval(0.3)
        settingsStore.saveNow()
    }

    func isPointerInsidePanel() -> Bool {
        NSMouseInRect(NSEvent.mouseLocation, panel.frame, false)
    }

    /// Tracking areas occasionally miss an exit when the window resizes underneath the
    /// pointer, so a slow poll backs them up while the panel is open.
    private func startPointerWatchdog() {
        stopPointerWatchdog()
        pointerWatchdog = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isExpanded else { return }
                if !self.isPointerInsidePanel(), self.closeTask == nil {
                    self.scheduleClose()
                }
            }
        }
    }

    private func stopPointerWatchdog() {
        pointerWatchdog?.invalidate()
        pointerWatchdog = nil
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        guard settingsStore.settings.closeOnOutsideClick else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isExpanded, !self.isDragging,
                      !self.settingsStore.settings.isPinned else { return }
                guard !self.isPointerInsidePanel() else { return }
                self.close(immediate: true)
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
}

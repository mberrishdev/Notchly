import SwiftUI
import WebKit

struct WebWidgetView: NSViewRepresentable {
    let package: WebWidgetPackage
    let environment: AppEnvironment
    @Binding var measuredHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(package: package, environment: environment) { height in
            // Cheap animation only when the change is meaningful, so a widget that
            // reports its height every frame doesn't make the panel wobble.
            if abs(height - measuredHeight) > 2 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { measuredHeight = height }
            }
        }
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(package: package)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let container = NSView()
        private var webView: WKWebView?
        private let bridge: WebWidgetBridge
        private let environment: AppEnvironment
        private var package: WebWidgetPackage
        private var loadedRevision: Int = -1
        private var appliedTheme: String = ""
        private var appliedNetworkPolicy: Bool?
        private var refreshTimer: Timer?

        private static var ruleListCache: WKContentRuleList?

        init(package: WebWidgetPackage, environment: AppEnvironment, onResize: @escaping (CGFloat) -> Void) {
            self.package = package
            self.environment = environment
            self.bridge = WebWidgetBridge(widgetID: package.id, environment: environment)
            super.init()
            container.wantsLayer = true
            bridge.onResize = onResize
            bridge.onClose = { NotificationCenter.default.post(name: .notchlyRequestClose, object: nil) }
            build()
        }

        private func build() {
            let configuration = WKWebViewConfiguration()
            let controller = WKUserContentController()
            configuration.userContentController = controller
            configuration.suppressesIncrementalRendering = false
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true

            // Each widget gets its own storage jar so one can't read another's state.
            configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.storeIdentifier(for: package.id))

            controller.addScriptMessageHandler(bridge, contentWorld: .page, name: "notchly")
            installUserScripts(into: controller)

            let webView = WKWebView(frame: container.bounds, configuration: configuration)
            webView.autoresizingMask = [.width, .height]
            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.setValue(false, forKey: "drawsBackground")
            webView.underPageBackgroundColor = .clear
            webView.isInspectable = environment.settings.settings.enableWebInspector
            webView.allowsBackForwardNavigationGestures = false
            container.addSubview(webView)
            self.webView = webView

            applyNetworkPolicy()
            load(force: true)
            scheduleRefresh()
        }

        private func installUserScripts(into controller: WKUserContentController) {
            let theme = environment.themeJSON()
            appliedTheme = theme
            let autoHeight = package.manifest.height == nil
            controller.addUserScript(WKUserScript(source: WebWidgetRuntime.api(theme: theme, autoHeight: autoHeight),
                                                  injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true))
            controller.addUserScript(WKUserScript(source: WebWidgetRuntime.baseStyle,
                                                  injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true))
        }

        /// Widgets without network permission get a content blocker rather than a
        /// promise not to phone home.
        private func applyNetworkPolicy() {
            guard let webView else { return }
            let granted = environment.isPermissionGranted(.network, for: package.id)
            // `update` runs on every SwiftUI pass; only touch WebKit when it changed.
            guard granted != appliedNetworkPolicy else { return }
            appliedNetworkPolicy = granted
            let controller = webView.configuration.userContentController
            controller.removeAllContentRuleLists()
            guard !granted else { return }

            if let cached = Self.ruleListCache {
                controller.add(cached)
                return
            }
            WKContentRuleListStore.default()?.compileContentRuleList(
                forIdentifier: "notchly-offline",
                encodedContentRuleList: WebWidgetRuntime.offlineRuleList
            ) { list, _ in
                guard let list else { return }
                Task { @MainActor in
                    Self.ruleListCache = list
                    controller.add(list)
                }
            }
        }

        private static func storeIdentifier(for widgetID: String) -> UUID {
            // Deterministic UUID so a widget keeps its localStorage across launches.
            var bytes = Array(widgetID.utf8)
            var digest = [UInt8](repeating: 0, count: 16)
            for (index, byte) in bytes.enumerated() {
                digest[index % 16] = digest[index % 16] &+ byte &* UInt8(truncatingIfNeeded: index &+ 1)
            }
            bytes.removeAll()
            digest[6] = (digest[6] & 0x0F) | 0x40
            digest[8] = (digest[8] & 0x3F) | 0x80
            return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                               digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
        }

        func update(package: WebWidgetPackage) {
            let revisionChanged = package.revision != self.package.revision
            let entryChanged = package.entryURL != self.package.entryURL
            self.package = package
            if revisionChanged || entryChanged { load(force: true) }

            let theme = environment.themeJSON()
            if theme != appliedTheme {
                appliedTheme = theme
                webView?.evaluateJavaScript("window.__notchlyApplyTheme && window.__notchlyApplyTheme(\(theme))")
            }
            applyNetworkPolicy()
            // The web view outlives a reload, so the inspector flag has to be re-applied
            // rather than only set when it was first built.
            webView?.isInspectable = environment.settings.settings.enableWebInspector
        }

        private func load(force: Bool) {
            guard let webView, force || loadedRevision != package.revision else { return }
            loadedRevision = package.revision
            let entry = package.entryURL
            guard FileManager.default.fileExists(atPath: entry.path) else {
                webView.loadHTMLString(Self.errorPage("Entry file \(package.manifest.entryFile) is missing."), baseURL: nil)
                return
            }
            webView.loadFileURL(entry, allowingReadAccessTo: package.folderURL)
        }

        private func scheduleRefresh() {
            refreshTimer?.invalidate()
            guard let interval = package.manifest.refreshInterval, interval > 0 else { return }
            refreshTimer = Timer.scheduledTimer(withTimeInterval: max(2, interval), repeats: true) { [weak self] _ in
                Task { @MainActor in self?.webView?.reload() }
            }
        }

        func teardown() {
            refreshTimer?.invalidate()
            webView?.configuration.userContentController.removeAllScriptMessageHandlers()
            webView?.stopLoading()
            webView?.removeFromSuperview()
            webView = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            environment.appendWidgetLog(widgetID: package.id, line: "Load failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }
            // Keep the widget inside its own folder; anything else opens in the browser.
            guard !url.isFileURL, navigationAction.navigationType != .other else { return .allow }
            NSWorkspace.shared.open(url)
            return .cancel
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
            return nil
        }

        private static func errorPage(_ message: String) -> String {
            """
            <html><body style="margin:0;font:13px -apple-system;color:rgba(255,255,255,0.7);padding:14px">
            \(message.replacingOccurrences(of: "<", with: "&lt;"))
            </body></html>
            """
        }
    }
}

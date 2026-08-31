import Foundation
import AppKit
import Combine

@MainActor
final class WebWidgetStore: ObservableObject {
    @Published private(set) var packages: [WebWidgetPackage] = []
    @Published private(set) var failures: [WebWidgetLoadFailure] = []
    @Published private(set) var lastScan: Date?

    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryDescriptor: CInt = -1
    private var folderSources: [String: DispatchSourceFileSystemObject] = [:]
    private var reloadDebounce: Task<Void, Never>?
    private var revisions: [String: Int] = [:]

    init() {}

    func start() {
        seedExamplesIfNeeded()
        scan()
        watchRoot()
    }

    func stop() {
        directorySource?.cancel(); directorySource = nil
        if directoryDescriptor >= 0 { close(directoryDescriptor); directoryDescriptor = -1 }
        folderSources.values.forEach { $0.cancel() }
        folderSources.removeAll()
    }

    func scan() {
        let root = AppPaths.widgetsDirectory
        let manager = FileManager.default
        var found: [WebWidgetPackage] = []
        var problems: [WebWidgetLoadFailure] = []

        let entries = (try? manager.contentsOfDirectory(at: root,
                                                        includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: [.skipsHiddenFiles])) ?? []

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: entry.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }

            let manifestURL = entry.appendingPathComponent("widget.json")
            guard manager.fileExists(atPath: manifestURL.path) else {
                problems.append(WebWidgetLoadFailure(folderURL: entry, reason: "No widget.json in this folder."))
                continue
            }
            do {
                let data = try Data(contentsOf: manifestURL)
                var manifest = try JSONDecoder().decode(WebWidgetManifest.self, from: data)
                manifest.id = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !manifest.id.isEmpty else {
                    problems.append(WebWidgetLoadFailure(folderURL: entry, reason: "widget.json needs a non-empty \"id\"."))
                    continue
                }
                guard manager.fileExists(atPath: entry.appendingPathComponent(manifest.entryFile).path) else {
                    problems.append(WebWidgetLoadFailure(folderURL: entry, reason: "Entry file \"\(manifest.entryFile)\" is missing."))
                    continue
                }
                if found.contains(where: { $0.id == manifest.id }) {
                    problems.append(WebWidgetLoadFailure(folderURL: entry, reason: "Another widget already uses the id \"\(manifest.id)\"."))
                    continue
                }
                found.append(WebWidgetPackage(manifest: manifest,
                                              folderURL: entry,
                                              revision: revisions[manifest.id] ?? 0))
            } catch let error as DecodingError {
                problems.append(WebWidgetLoadFailure(folderURL: entry, reason: Self.describe(error)))
            } catch {
                problems.append(WebWidgetLoadFailure(folderURL: entry, reason: error.localizedDescription))
            }
        }

        packages = found
        failures = problems
        lastScan = Date()
        watchFolders(found.map(\.folderURL))
        NotificationCenter.default.post(name: .notchlyWidgetsChanged, object: nil)
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _): return "widget.json is missing the required key \"\(key.stringValue)\"."
        case .typeMismatch(_, let context): return "widget.json: \(context.debugDescription)"
        case .valueNotFound(_, let context): return "widget.json: \(context.debugDescription)"
        case .dataCorrupted(let context): return "widget.json isn't valid JSON. \(context.debugDescription)"
        @unknown default: return "widget.json could not be read."
        }
    }

    /// Marks a widget dirty so its web view reloads on the next render pass.
    func bumpRevision(for id: String) {
        revisions[id, default: 0] += 1
        if let index = packages.firstIndex(where: { $0.id == id }) {
            packages[index].revision = revisions[id] ?? 0
        }
    }

    func reloadAll() {
        for package in packages { revisions[package.id, default: 0] += 1 }
        scan()
    }

    func package(id: String) -> WebWidgetPackage? {
        packages.first { $0.id == id }
    }

    private func watchRoot() {
        directorySource?.cancel()
        if directoryDescriptor >= 0 { close(directoryDescriptor) }
        let path = AppPaths.widgetsDirectory.path
        directoryDescriptor = open(path, O_EVTONLY)
        guard directoryDescriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: directoryDescriptor,
                                                               eventMask: [.write, .rename, .delete],
                                                               queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleRescan(bumpAll: false) }
        source.resume()
        directorySource = source
    }

    private func watchFolders(_ urls: [URL]) {
        let wanted = Set(urls.map(\.path))
        for (path, source) in folderSources where !wanted.contains(path) {
            source.cancel()
            folderSources.removeValue(forKey: path)
        }
        for url in urls where folderSources[url.path] == nil {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                                    eventMask: [.write, .rename, .delete, .attrib],
                                                                    queue: .main)
            source.setEventHandler { [weak self] in self?.scheduleRescan(bumpAll: true) }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            folderSources[url.path] = source
        }
    }

    /// Editors save in bursts (write, rename, chmod); coalesce them into one reload.
    private func scheduleRescan(bumpAll: Bool) {
        reloadDebounce?.cancel()
        reloadDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard let self, !Task.isCancelled else { return }
            if bumpAll { for package in self.packages { self.revisions[package.id, default: 0] += 1 } }
            self.scan()
        }
    }

    func revealInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: AppPaths.widgetsDirectory.path)
    }

    /// Copies the bundled starter widgets in on first launch so the folder is never
    /// an empty void the user has to guess at.
    private func seedExamplesIfNeeded() {
        let marker = AppPaths.supportDirectory.appendingPathComponent(".examples-installed")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        copyExamples(overwrite: false)
        try? Data().write(to: marker)
    }

    @discardableResult
    func copyExamples(overwrite: Bool) -> Int {
        guard let source = Bundle.main.url(forResource: "ExampleWidgets", withExtension: nil),
              let entries = try? FileManager.default.contentsOfDirectory(at: source,
                                                                         includingPropertiesForKeys: nil,
                                                                         options: [.skipsHiddenFiles]) else { return 0 }
        var copied = 0
        for entry in entries {
            let destination = AppPaths.widgetsDirectory.appendingPathComponent(entry.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                guard overwrite else { continue }
                try? FileManager.default.removeItem(at: destination)
            }
            if (try? FileManager.default.copyItem(at: entry, to: destination)) != nil { copied += 1 }
        }
        if copied > 0 { scan() }
        return copied
    }

    /// Scaffolds a new widget folder and returns it, ready to open in an editor.
    func createStarterWidget(named name: String) -> URL? {
        let slug = name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let folderName = slug.isEmpty ? "my-widget" : slug
        var folder = AppPaths.widgetsDirectory.appendingPathComponent(folderName)
        var suffix = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = AppPaths.widgetsDirectory.appendingPathComponent("\(folderName)-\(suffix)")
            suffix += 1
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let manifest = """
            {
              "id": "local.\(folder.lastPathComponent)",
              "name": "\(name.isEmpty ? "My Widget" : name)",
              "version": "1.0.0",
              "author": "\(NSFullUserName())",
              "description": "A custom widget.",
              "entry": "index.html",
              "icon": "sparkles",
              "height": 150,
              "permissions": ["system"],
              "settings": [
                { "key": "greeting", "type": "string", "label": "Greeting", "default": "Hello" }
              ]
            }
            """
            try manifest.write(to: folder.appendingPathComponent("widget.json"), atomically: true, encoding: .utf8)
            try Self.starterHTML.write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
            scan()
            return folder
        } catch {
            return nil
        }
    }

    private static let starterHTML = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        :root { color-scheme: dark; }
        body {
          margin: 0;
          font: 13px -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
          color: rgba(255,255,255,0.92);
          display: flex; flex-direction: column; gap: 10px;
          justify-content: center; padding: 14px;
        }
        h1 { font-size: 20px; font-weight: 600; margin: 0; letter-spacing: -0.02em; }
        p  { margin: 0; color: rgba(255,255,255,0.55); }
        .row { display: flex; gap: 8px; align-items: baseline; }
        .val { font-variant-numeric: tabular-nums; font-weight: 600; }
        button {
          appearance: none; border: 0; border-radius: 8px; padding: 7px 12px;
          background: var(--notchly-accent, #6E9BFF); color: #06070A;
          font: inherit; font-weight: 600; cursor: pointer;
        }
        button:active { transform: scale(0.97); }
      </style>
    </head>
    <body>
      <h1 id="greeting">Hello</h1>
      <p>Edit <code>index.html</code> and this panel reloads itself.</p>
      <div class="row"><span>CPU</span><span class="val" id="cpu">--</span></div>
      <button id="tick">Count: <span id="count">0</span></button>

      <script>
        (async () => {
          const greeting = await notchly.settings.get('greeting');
          document.getElementById('greeting').textContent = greeting ?? 'Hello';

          async function refresh() {
            const stats = await notchly.system.stats();
            document.getElementById('cpu').textContent = Math.round(stats.cpu.total * 100) + '%';
          }
          refresh();
          setInterval(refresh, 2000);

          let count = (await notchly.storage.get('count')) ?? 0;
          const label = document.getElementById('count');
          label.textContent = count;
          document.getElementById('tick').onclick = async () => {
            count += 1;
            label.textContent = count;
            await notchly.storage.set('count', count);
          };
        })();
      </script>
    </body>
    </html>
    """
}

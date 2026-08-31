import AppKit
import WebKit
import UserNotifications

@MainActor
final class WebWidgetBridge: NSObject, WKScriptMessageHandlerWithReply {
    let widgetID: String
    private weak var environment: AppEnvironment?
    private var storage: [String: JSONValue]
    private let storageURL: URL
    private var saveTask: Task<Void, Never>?

    var onResize: ((CGFloat) -> Void)?
    var onClose: (() -> Void)?

    init(widgetID: String, environment: AppEnvironment) {
        self.widgetID = widgetID
        self.environment = environment
        self.storageURL = AppPaths.widgetStorageDirectory.appendingPathComponent("\(widgetID).json")
        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
            storage = decoded
        } else {
            storage = [:]
        }
        super.init()
    }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any],
              let method = body["method"] as? String else {
            return (nil, "Malformed call to window.notchly.")
        }
        let params = body["params"] as? [String: Any] ?? [:]
        do {
            return (try await handle(method: method, params: params), nil)
        } catch let error as BridgeError {
            return (nil, error.message)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private struct BridgeError: Error { var message: String }

    private func require(_ permission: WidgetPermission) throws {
        guard let environment else { throw BridgeError(message: "Notchly is shutting down.") }
        guard environment.isPermissionGranted(permission, for: widgetID) else {
            throw BridgeError(message: "This widget hasn't been granted \"\(permission.label)\". Enable it in Notchly ▸ Settings ▸ Widgets.")
        }
    }

    private func handle(method: String, params: [String: Any]) async throws -> Any? {
        guard let environment else { throw BridgeError(message: "Notchly is shutting down.") }

        switch method {
        case "system.stats":
            try require(.system)
            return environment.systemStatsPayload()

        case "system.info":
            return [
                "hostName": ProcessInfo.processInfo.hostName,
                "userName": NSFullUserName(),
                "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
                "appearance": environment.isDarkAppearance ? "dark" : "light"
            ]
        case "storage.get":
            guard let key = params["key"] as? String else { throw BridgeError(message: "storage.get needs a key.") }
            return storage[key]?.anyValue

        case "storage.set":
            guard let key = params["key"] as? String else { throw BridgeError(message: "storage.set needs a key.") }
            if let value = params["value"], !(value is NSNull) {
                storage[key] = JSONValue(any: value)
            } else {
                storage[key] = .null
            }
            scheduleStorageSave()
            return true

        case "storage.remove":
            guard let key = params["key"] as? String else { throw BridgeError(message: "storage.remove needs a key.") }
            storage.removeValue(forKey: key)
            scheduleStorageSave()
            return true

        case "storage.keys":
            return Array(storage.keys).sorted()

        case "storage.clear":
            storage.removeAll()
            scheduleStorageSave()
            return true
        case "settings.get":
            guard let key = params["key"] as? String else { throw BridgeError(message: "settings.get needs a key.") }
            return environment.widgetSetting(key: key, widgetID: widgetID)?.anyValue

        case "settings.all":
            return environment.widgetSettings(widgetID: widgetID).mapValues(\.anyValue)
        case "media.now":
            return environment.mediaPayload()

        case "media.playPause":
            environment.media.playPause(); return true
        case "media.next":
            environment.media.next(); return true
        case "media.previous":
            environment.media.previous(); return true
        case "clipboard.history":
            try require(.clipboard)
            let limit = (params["limit"] as? Int) ?? 20
            return environment.clipboard.items.prefix(limit).map { item in
                [
                    "id": item.id.uuidString,
                    "kind": item.kind.rawValue,
                    "text": item.text,
                    "createdAt": item.createdAt.timeIntervalSince1970,
                    "source": item.sourceName ?? ""
                ] as [String: Any]
            }

        case "clipboard.write":
            guard let text = params["text"] as? String else { throw BridgeError(message: "clipboard.write needs text.") }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return true
        case "shell.run":
            try require(.shell)
            guard let command = params["command"] as? String, !command.isEmpty else {
                throw BridgeError(message: "shell.run needs a command.")
            }
            let timeout = (params["timeout"] as? Double) ?? 10
            return await Self.runShell(command, timeout: min(max(timeout, 0.5), 60))
        case "open.url":
            guard let raw = params["url"] as? String, let url = URL(string: raw) else {
                throw BridgeError(message: "open.url needs a valid url.")
            }
            guard let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto", "file"].contains(scheme) else {
                throw BridgeError(message: "Only http, https, mailto and file URLs can be opened.")
            }
            NSWorkspace.shared.open(url)
            return true

        case "notify":
            try require(.notifications)
            let title = params["title"] as? String ?? "Notchly"
            let body = params["body"] as? String ?? ""
            Notifier.post(title: title, body: body)
            return true
        case "http.get":
            try require(.network)
            guard let raw = params["url"] as? String, let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
                throw BridgeError(message: "http.get needs an http(s) url.")
            }
            var request = URLRequest(url: url, timeoutInterval: 15)
            if let headers = params["headers"] as? [String: String] {
                headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                return ["status": status, "body": String(decoding: data, as: UTF8.self)] as [String: Any]
            } catch {
                throw BridgeError(message: error.localizedDescription)
            }
        case "ui.resize":
            guard let height = params["height"] as? Double else { throw BridgeError(message: "ui.resize needs a height.") }
            onResize?(CGFloat(min(max(height, 24), 900)))
            return true

        case "ui.close":
            onClose?()
            return true

        case "ui.theme":
            return environment.themePayload()

        case "ui.holdOpen":
            let hold = (params["value"] as? Bool) ?? true
            environment.setHoldOpen(hold, owner: "web:\(widgetID)")
            return true

        case "log":
            let text = params["message"] as? String ?? ""
            environment.appendWidgetLog(widgetID: widgetID, line: text)
            return true

        default:
            throw BridgeError(message: "Unknown method \"\(method)\".")
        }
    }

    private func scheduleStorageSave() {
        saveTask?.cancel()
        let snapshot = storage
        let url = storageURL
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func runShell(_ command: String, timeout: TimeInterval) async -> [String: Any] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-lc", command]
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do { try process.run() } catch {
                    return continuation.resume(returning: ["code": -1, "stdout": "", "stderr": error.localizedDescription])
                }
                let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                killer.cancel()
                continuation.resume(returning: [
                    "code": Int(process.terminationStatus),
                    "stdout": String(decoding: outData, as: UTF8.self),
                    "stderr": String(decoding: errData, as: UTF8.self)
                ])
            }
        }
    }
}

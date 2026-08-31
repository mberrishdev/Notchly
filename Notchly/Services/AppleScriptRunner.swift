import Foundation

enum AppleScriptError: Error {
    case launchFailed
    case notAuthorized
    case failed(String)

    /// True when macOS blocked the Apple event because the user hasn't granted
    /// Automation access (or explicitly denied it).
    var isAuthorizationFailure: Bool {
        if case .notAuthorized = self { return true }
        return false
    }
}

/// Runs AppleScript out of process.
///
/// `NSAppleScript` would block whichever thread it runs on until the target app
/// answers, and a busy media player can take seconds — long enough to visibly stall the
/// panel. Shelling out to `osascript` keeps all of that off the main thread.

enum AppleScriptRunner {
    static func run(_ source: String, timeout: TimeInterval = 5) async -> Result<String, AppleScriptError> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: execute(source, timeout: timeout))
            }
        }
    }

    /// Runs a script that is expected to leave a file behind, and returns its contents.
    static func runWritingFile(timeout: TimeInterval = 8,
                               _ makeSource: @Sendable (String) -> String) async -> Data? {
        let path = NSTemporaryDirectory() + "notchly-\(UUID().uuidString)"
        let source = makeSource(path)
        let result = await run(source, timeout: timeout)
        defer { try? FileManager.default.removeItem(atPath: path) }
        guard case .success = result else { return nil }
        return FileManager.default.contents(atPath: path)
    }

    private static func execute(_ source: String, timeout: TimeInterval) -> Result<String, AppleScriptError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do { try process.run() } catch { return .failure(.launchFailed) }

        // Guard against a hung target application wedging the poll loop forever.
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)

        let outData = output.fileHandleForReading.readDataToEndOfFile()
        let errData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: errData, as: UTF8.self)
            // -1743 is errAEEventNotPermitted; -600/-609 mean the app went away mid-call.
            if message.contains("-1743") || message.lowercased().contains("not allowed") {
                return .failure(.notAuthorized)
            }
            return .failure(.failed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return .success(String(decoding: outData, as: UTF8.self))
    }
}

import AppKit
import Combine

@MainActor
final class MediaController: ObservableObject {
    enum Player: String, Equatable, Sendable, CaseIterable {
        case music = "Music"
        case spotify = "Spotify"
        case system = "System"

        var bundleID: String? {
            switch self {
            case .music: return "com.apple.Music"
            case .spotify: return "com.spotify.client"
            case .system: return nil
            }
        }

        /// Name to address the app by in AppleScript, or nil when it isn't scriptable.
        var scriptName: String? { bundleID == nil ? nil : rawValue }

        var symbol: String {
            switch self {
            case .music: return "music.note"
            case .spotify: return "waveform"
            case .system: return "speaker.wave.2.fill"
            }
        }
    }

    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var automationDenied = false

    /// `live` backs the open Panel, which needs a moving progress bar and so has to
    /// poll. `ambient` backs the Idle handle, which only needs to know whether anything
    /// is playing — that arrives as a notification, so it polls once a minute purely as
    /// a backstop for a player that doesn't announce itself.
    enum Cadence {
        case live, ambient
        var interval: TimeInterval { self == .live ? 1.5 : 60 }
    }

    private var liveSubscribers = 0
    private var ambientSubscribers = 0
    private var runningCadence: Cadence?
    private var timer: Timer?
    private var playbackObservers: [NSObjectProtocol] = []
    private var pollTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var lastArtworkKey: String?

    init() {}

    func subscribe(_ cadence: Cadence) {
        switch cadence {
        case .live: liveSubscribers += 1
        case .ambient: ambientSubscribers += 1
        }
        applyCadence()
    }

    func unsubscribe(_ cadence: Cadence) {
        switch cadence {
        case .live: liveSubscribers = max(0, liveSubscribers - 1)
        case .ambient: ambientSubscribers = max(0, ambientSubscribers - 1)
        }
        applyCadence()
    }

    private func applyCadence() {
        let wanted: Cadence? = liveSubscribers > 0 ? .live : (ambientSubscribers > 0 ? .ambient : nil)
        guard wanted != runningCadence else { return }
        runningCadence = wanted

        timer?.invalidate(); timer = nil
        guard let wanted else {
            pollTask?.cancel(); pollTask = nil
            stopObservingPlayback()
            return
        }
        startObservingPlayback()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: wanted.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer?.tolerance = wanted.interval / 4
    }

    private func poll() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            let result = await Self.readNowPlaying()
            await MainActor.run {
                guard let self else { return }
                self.pollTask = nil
                switch result {
                case .success(let value):
                    self.automationDenied = false
                    if self.nowPlaying != value { self.nowPlaying = value }
                    self.refreshArtworkIfNeeded(for: value)
                case .denied:
                    self.automationDenied = true
                    self.nowPlaying = nil
                    self.artwork = nil
                case .nothing:
                    self.nowPlaying = nil
                    self.artwork = nil
                    self.lastArtworkKey = nil
                }
            }
        }
    }

    /// Music and Spotify both broadcast when playback changes, which turns the common
    /// case from "spawn `osascript` on a timer forever" into "ask once, when something
    /// actually happened".
    private static let playbackNotifications = [
        "com.apple.iTunes.playerInfo",
        "com.spotify.client.PlaybackStateChanged"
    ]

    private func startObservingPlayback() {
        guard playbackObservers.isEmpty else { return }
        playbackObservers = Self.playbackNotifications.map { name in
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.poll() }
            }
        }
    }

    private func stopObservingPlayback() {
        playbackObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        playbackObservers.removeAll()
    }

    private enum PollResult { case success(NowPlaying), denied, nothing }

    private static func readNowPlaying() async -> PollResult {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var sawDenial = false

        // Prefer whichever scriptable player is actually playing right now.
        var paused: NowPlaying?
        for player in [Player.spotify, .music] {
            guard let bundleID = player.bundleID, running.contains(bundleID) else { continue }
            switch await AppleScriptRunner.run(script(for: player)) {
            case .failure(let error):
                if error.isAuthorizationFailure { sawDenial = true }
            case .success(let output):
                guard let parsed = parse(output, player: player) else { continue }
                if parsed.isPlaying { return .success(parsed) }
                if paused == nil { paused = parsed }
            }
        }
        if let paused { return .success(paused) }
        return sawDenial ? .denied : .nothing
    }

    private static func script(for player: Player) -> String {
        let name = player.rawValue
        // A single record keeps this to one Apple event per poll.
        return """
        tell application "\(name)"
            if it is running then
                try
                    set st to (player state as text)
                    set t to name of current track
                    set ar to artist of current track
                    set al to album of current track
                    set dur to duration of current track
                    set pos to player position
                    return st & "\u{1F}" & t & "\u{1F}" & ar & "\u{1F}" & al & "\u{1F}" & (dur as text) & "\u{1F}" & (pos as text)
                on error
                    return "none"
                end try
            else
                return "none"
            end if
        end tell
        """
    }

    private static func parse(_ output: String, player: Player) -> NowPlaying? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "none" else { return nil }
        let parts = trimmed.components(separatedBy: "\u{1F}")
        guard parts.count >= 6 else { return nil }

        var duration = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
        // Spotify reports track length in milliseconds; Music reports seconds.
        if player == .spotify, duration > 3_600 { duration /= 1000 }
        let position = Double(parts[5].replacingOccurrences(of: ",", with: ".")) ?? 0
        let title = parts[1]
        guard !title.isEmpty else { return nil }

        return NowPlaying(app: player,
                          title: title,
                          artist: parts[2],
                          album: parts[3],
                          isPlaying: parts[0].lowercased().contains("playing"),
                          duration: duration,
                          position: position,
                          artworkKey: "\(player.rawValue)|\(parts[2])|\(parts[3])|\(title)")
    }

    private func refreshArtworkIfNeeded(for track: NowPlaying) {
        guard track.artworkKey != lastArtworkKey else { return }
        lastArtworkKey = track.artworkKey
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            let image = await Self.fetchArtwork(for: track)
            await MainActor.run {
                guard let self, self.lastArtworkKey == track.artworkKey else { return }
                self.artwork = image
            }
        }
    }

    private static func fetchArtwork(for track: NowPlaying) async -> NSImage? {
        switch track.app {
        case .spotify:
            // Spotify exposes an https artwork URL, which is far cheaper than raw data.
            let script = """
            tell application "Spotify"
                try
                    return artwork url of current track
                on error
                    return ""
                end try
            end tell
            """
            guard case .success(let urlString) = await AppleScriptRunner.run(script),
                  let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme == "https" else { return nil }
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return NSImage(data: data)
        case .music:
            // Music only exposes artwork as raw data, so have the script spool it to disk.
            let data = await AppleScriptRunner.runWritingFile { (path: String) in
                """
                tell application "Music"
                    try
                        set d to raw data of artwork 1 of current track
                    on error
                        return "none"
                    end try
                end tell
                set f to open for access POSIX file "\(path)" with write permission
                set eof f to 0
                write d to f
                close access f
                return "ok"
                """
            }
            guard let data, !data.isEmpty else { return nil }
            return NSImage(data: data)
        case .system:
            return nil
        }
    }

    func playPause() { command("playpause", key: NX_KEYTYPE_PLAY) }
    func next() { command("next track", key: NX_KEYTYPE_NEXT) }
    func previous() { command("previous track", key: NX_KEYTYPE_PREVIOUS) }

    func seek(to fraction: Double) {
        guard let track = nowPlaying, track.duration > 0, let name = track.app.scriptName else { return }
        let seconds = fraction * track.duration
        Task {
            _ = await AppleScriptRunner.run("tell application \"\(name)\" to set player position to \(seconds)")
            await MainActor.run { self.poll() }
        }
    }

    func revealPlayer() {
        guard let bundleID = nowPlaying?.app.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func command(_ appleScriptVerb: String, key: Int32) {
        if let name = nowPlaying?.app.scriptName {
            let previous = nowPlaying
            Task {
                _ = await AppleScriptRunner.run("tell application \"\(name)\" to \(appleScriptVerb)")
                // Optimistically flip the play state so the button feels instant.
                await MainActor.run {
                    if appleScriptVerb == "playpause", var current = self.nowPlaying, current == previous {
                        current.isPlaying.toggle()
                        self.nowPlaying = current
                    }
                    self.poll()
                }
            }
        } else {
            MediaKey.post(key)
        }
    }
}

/// Synthesised media keys for players we can't script. Needs Accessibility access;
/// without it the post is silently dropped, which is why it's only the fallback path.

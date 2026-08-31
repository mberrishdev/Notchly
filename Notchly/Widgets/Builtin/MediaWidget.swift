import SwiftUI

struct MediaWidget: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var media: MediaController
    @EnvironmentObject private var settings: SettingsStore
    @State private var scrubValue: Double?

    private var prefs: WidgetPreferences { WidgetPreferences(widgetID: "media", environment: environment) }

    var body: some View {
        WidgetCard(title: "Now Playing", symbol: "play.circle") {
            Group {
                if let track = media.nowPlaying {
                    playing(track)
                } else if media.automationDenied {
                    permissionPrompt
                } else {
                    EmptyStateView(symbol: "music.note",
                                   title: "Nothing playing",
                                   detail: "Start something in Music or Spotify.")
                }
            }
            .animation(Theme.contentTransition, value: media.nowPlaying?.title)
        }
    }

    private func playing(_ track: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if prefs.bool("showArtwork", default: true) {
                    artwork(track)
                }
                VStack(alignment: .leading, spacing: 3) {
                    MarqueeText(text: track.title,
                                font: .system(size: 13, weight: .semibold),
                                color: Theme.primaryText)
                    Text(track.artist.isEmpty ? track.app.rawValue : track.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                    if !track.album.isEmpty {
                        Text(track.album)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            if track.duration > 0 {
                progress(track)
            }

            HStack(spacing: 8) {
                Button(action: media.revealPlayer) {
                    HStack(spacing: 4) {
                        Image(systemName: track.app.symbol).font(.system(size: 9))
                        Text(track.app.rawValue).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Bring \(track.app.rawValue) to the front")

                Spacer(minLength: 0)

                IconButton(symbol: "backward.fill", size: 11, help: "Previous") { media.previous() }
                IconButton(symbol: track.isPlaying ? "pause.fill" : "play.fill",
                           size: 12, diameter: 32, isProminent: true,
                           help: track.isPlaying ? "Pause" : "Play") { media.playPause() }
                IconButton(symbol: "forward.fill", size: 11, help: "Next") { media.next() }
            }
        }
    }

    @ViewBuilder
    private func artwork(_ track: NowPlaying) -> some View {
        ZStack {
            if let image = media.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                LinearGradient(colors: [settings.settings.accentColor.opacity(0.35),
                                        settings.settings.accentColor.opacity(0.08)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: track.app.symbol)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .animation(.easeOut(duration: 0.25), value: media.artwork)
    }

    private func progress(_ track: NowPlaying) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let fraction = scrubValue ?? track.progress
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(settings.settings.accentColor)
                        .frame(width: max(3, geo.size.width * CGFloat(fraction)))
                }
                .contentShape(Rectangle().inset(by: -6))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubValue = min(max(Double(value.location.x / max(geo.size.width, 1)), 0), 1)
                        }
                        .onEnded { _ in
                            if let scrubValue { media.seek(to: scrubValue) }
                            scrubValue = nil
                        }
                )
            }
            .frame(height: 4)
            .animation(scrubValue == nil ? .linear(duration: 0.9) : nil, value: track.position)

            HStack {
                Text(timecode((scrubValue ?? track.progress) * track.duration))
                Spacer(minLength: 0)
                Text("-" + timecode(max(0, track.duration - (scrubValue ?? track.progress) * track.duration)))
            }
            .font(.system(size: 9.5))
            .monospacedDigit()
            .foregroundStyle(Theme.tertiaryText)
        }
    }

    private func timecode(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static let automationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    )

    private func openAutomationSettings() {
        guard let url = Self.automationSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notchly needs permission to read what's playing.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: openAutomationSettings) {
                Text("Open Privacy Settings")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(settings.settings.accentColor))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

/// Scrolls long titles horizontally, but only while the pointer is over them — constant
/// motion in a panel that's always on screen gets old fast.

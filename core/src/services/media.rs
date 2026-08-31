//! What is playing, and transport control.
//!
//! macOS goes through `osascript` as a subprocess rather than `NSAppleScript` or the
//! private MediaRemote framework: a busy player can take seconds to answer an Apple
//! event, which would stall whichever thread ran it.
//!
//! Windows has a real public API for this — `GlobalSystemMediaTransportControlsSession`
//! — so that side needs no subprocess, no scripting dialect, and no permission prompt.

use serde_json::Value;

/// A transport command, named for what the user means rather than for how either
/// platform happens to spell it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Transport {
    PlayPause,
    Next,
    Previous,
}

#[cfg(target_os = "macos")]
const PLAYERS: [&str; 2] = ["Spotify", "Music"];

/// Reads the current track. Returns `{ "playing": false }` when nothing is playing or
/// the user hasn't granted Automation access.
#[cfg(target_os = "macos")]
pub fn now_playing() -> Value {
    {
        let mut paused: Option<Value> = None;
        for player in PLAYERS {
            let Some(output) = run_script(&now_playing_script(player)) else { continue };
            let Some(track) = parse(&output, player) else { continue };
            if track["playing"].as_bool().unwrap_or(false) {
                return track;
            }
            paused.get_or_insert(track);
        }
        paused.unwrap_or_else(|| serde_json::json!({ "playing": false }))
    }
}

#[cfg(target_os = "macos")]
pub fn transport(command: Transport) {
    let verb = match command {
        Transport::PlayPause => "playpause",
        Transport::Next => "next track",
        Transport::Previous => "previous track",
    };
    // Send to whichever player is actually playing, so a paused Spotify in the
    // background doesn't swallow a command meant for Music.
    let target = PLAYERS.iter().find(|player| {
        run_script(&format!(
            "tell application \"{player}\"\n if it is running then return (player state as text)\n end if\n return \"none\"\nend tell"
        ))
        .map(|state| state.trim() == "playing")
        .unwrap_or(false)
    });
    let player = target.copied().unwrap_or("Spotify");
    let _ = run_script(&format!("tell application \"{player}\" to {verb}"));
}

#[cfg(target_os = "macos")]
fn now_playing_script(player: &str) -> String {
    // One record per poll keeps this to a single Apple event.
    format!(
        r#"tell application "{player}"
    if it is running then
        try
            set st to (player state as text)
            set t to name of current track
            set ar to artist of current track
            set al to album of current track
            set dur to duration of current track
            set pos to player position
            return st & "|" & t & "|" & ar & "|" & al & "|" & (dur as text) & "|" & (pos as text)
        on error
            return "none"
        end try
    else
        return "none"
    end if
end tell"#
    )
}

#[cfg(target_os = "macos")]
fn run_script(source: &str) -> Option<String> {
    use std::process::{Command, Stdio};
    let output = Command::new("/usr/bin/osascript")
        .arg("-e")
        .arg(source)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).to_string())
}

#[cfg(target_os = "macos")]
fn parse(output: &str, player: &str) -> Option<Value> {
    let trimmed = output.trim();
    if trimmed == "none" || trimmed.is_empty() {
        return None;
    }
    let parts: Vec<&str> = trimmed.split('|').collect();
    if parts.len() < 6 {
        return None;
    }
    let title = parts[1];
    if title.is_empty() {
        return None;
    }
    let mut duration: f64 = parts[4].replace(',', ".").parse().unwrap_or(0.0);
    // Spotify reports track length in milliseconds; Music reports seconds.
    if player == "Spotify" && duration > 3600.0 {
        duration /= 1000.0;
    }
    Some(serde_json::json!({
        "playing": parts[0].to_lowercase().contains("playing"),
        "title": title,
        "artist": parts[2],
        "album": parts[3],
        "duration": duration,
        "position": parts[5].replace(',', ".").parse::<f64>().unwrap_or(0.0),
        "app": player,
    }))
}

#[cfg(test)]
#[cfg(target_os = "macos")]
mod tests {
    use super::*;

    #[test]
    fn parses_a_track_record() {
        let track = parse("playing|Song|Artist|Album|210.5|12.25", "Music").unwrap();
        assert_eq!(track["playing"], serde_json::json!(true));
        assert_eq!(track["title"], serde_json::json!("Song"));
        assert_eq!(track["duration"], serde_json::json!(210.5));
    }

    #[test]
    fn converts_spotify_milliseconds_to_seconds() {
        let track = parse("playing|S|A|B|210500|10", "Spotify").unwrap();
        assert_eq!(track["duration"], serde_json::json!(210.5));
    }

    #[test]
    fn music_seconds_are_left_alone() {
        let track = parse("paused|S|A|B|210.5|10", "Music").unwrap();
        assert_eq!(track["duration"], serde_json::json!(210.5));
        assert_eq!(track["playing"], serde_json::json!(false));
    }

    #[test]
    fn nothing_playing_and_malformed_output_yield_none() {
        assert!(parse("none", "Music").is_none());
        assert!(parse("", "Music").is_none());
        assert!(parse("playing|only|three", "Music").is_none());
        assert!(parse("playing||A|B|1|0", "Music").is_none());
    }
}

/// Windows keeps a system-wide picture of what is playing, so unlike macOS there is no
/// subprocess, no scripting dialect, and no per-application permission prompt. Whatever
/// holds the media session answers — Spotify, a browser tab, anything.
#[cfg(target_os = "windows")]
mod win {
    use super::Transport;
    use serde_json::{json, Value};
    use windows::Media::Control::{
        GlobalSystemMediaTransportControlsSession as Session,
        GlobalSystemMediaTransportControlsSessionManager as Manager,
        GlobalSystemMediaTransportControlsSessionPlaybackStatus as Status,
    };

    fn current_session() -> Option<Session> {
        Manager::RequestAsync().ok()?.get().ok()?.GetCurrentSession().ok()
    }

    pub fn now_playing() -> Value {
        let Some(session) = current_session() else {
            return json!({ "playing": false });
        };
        let Ok(properties) = session.TryGetMediaPropertiesAsync().and_then(|op| op.get()) else {
            return json!({ "playing": false });
        };

        let text = |value: windows::core::Result<windows::core::HSTRING>| {
            value.map(|s| s.to_string()).unwrap_or_default()
        };
        let title = text(properties.Title());
        if title.is_empty() {
            return json!({ "playing": false });
        }

        let playing = session
            .GetPlaybackInfo()
            .and_then(|info| info.PlaybackStatus())
            .map(|status| status == Status::Playing)
            .unwrap_or(false);

        // Timeline values are TimeSpans in 100-nanosecond ticks.
        let seconds = |ticks: i64| ticks as f64 / 10_000_000.0;
        let (duration, position) = session
            .GetTimelineProperties()
            .map(|timeline| {
                let start = timeline.StartTime().map(|t| t.Duration).unwrap_or(0);
                let end = timeline.EndTime().map(|t| t.Duration).unwrap_or(0);
                let now = timeline.Position().map(|t| t.Duration).unwrap_or(0);
                (seconds(end - start), seconds(now - start))
            })
            .unwrap_or((0.0, 0.0));

        json!({
            "playing": playing,
            "title": title,
            "artist": text(properties.Artist()),
            "album": text(properties.AlbumTitle()),
            "duration": duration.max(0.0),
            "position": position.max(0.0),
            "app": session.SourceAppUserModelId().map(|s| s.to_string()).unwrap_or_default(),
        })
    }

    pub fn transport(command: Transport) {
        let Some(session) = current_session() else { return };
        // Fire and forget: the poll picks the new state up on its next tick.
        let _ = match command {
            Transport::PlayPause => session.TryTogglePlayPauseAsync().map(|_| ()),
            Transport::Next => session.TrySkipNextAsync().map(|_| ()),
            Transport::Previous => session.TrySkipPreviousAsync().map(|_| ()),
        };
    }
}

#[cfg(target_os = "windows")]
pub fn now_playing() -> Value {
    win::now_playing()
}

#[cfg(target_os = "windows")]
pub fn transport(command: Transport) {
    win::transport(command)
}

/// Platforms with no media integration report nothing rather than pretending.
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn now_playing() -> Value {
    serde_json::json!({ "playing": false })
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn transport(_command: Transport) {}

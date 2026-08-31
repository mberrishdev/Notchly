//! What is playing, and transport control.
//!
//! macOS goes through `osascript` as a subprocess rather than `NSAppleScript` or the
//! private MediaRemote framework: a busy player can take seconds to answer an Apple
//! event, which would stall whichever thread ran it.
//!
//! Windows has a real public API for this — `GlobalSystemMediaTransportControlsSession`
//! — so the port gets to delete the ugliest code in the project. That lands with the
//! Windows pass; until then it reports nothing rather than pretending.

use serde_json::{json, Value};

#[cfg(target_os = "macos")]
const PLAYERS: [&str; 2] = ["Spotify", "Music"];

/// Reads the current track. Returns `{ "playing": false }` when nothing is playing or
/// the user hasn't granted Automation access.
pub fn now_playing() -> Value {
    #[cfg(target_os = "macos")]
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
        paused.unwrap_or_else(|| json!({ "playing": false }))
    }
    #[cfg(not(target_os = "macos"))]
    {
        json!({ "playing": false })
    }
}

pub fn transport(verb: &str) {
    #[cfg(target_os = "macos")]
    {
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
    #[cfg(not(target_os = "macos"))]
    {
        let _ = verb;
    }
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
    Some(json!({
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
        assert_eq!(track["playing"], json!(true));
        assert_eq!(track["title"], json!("Song"));
        assert_eq!(track["duration"], json!(210.5));
    }

    #[test]
    fn converts_spotify_milliseconds_to_seconds() {
        let track = parse("playing|S|A|B|210500|10", "Spotify").unwrap();
        assert_eq!(track["duration"], json!(210.5));
    }

    #[test]
    fn music_seconds_are_left_alone() {
        let track = parse("paused|S|A|B|210.5|10", "Music").unwrap();
        assert_eq!(track["duration"], json!(210.5));
        assert_eq!(track["playing"], json!(false));
    }

    #[test]
    fn nothing_playing_and_malformed_output_yield_none() {
        assert!(parse("none", "Music").is_none());
        assert!(parse("", "Music").is_none());
        assert!(parse("playing|only|three", "Music").is_none());
        assert!(parse("playing||A|B|1|0", "Music").is_none());
    }
}

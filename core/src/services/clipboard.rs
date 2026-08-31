//! Clipboard history.
//!
//! This is the one service outside the refcounted sampling scheme: it has to run
//! whenever the app does, because a history with gaps in it is not a history.

use crate::panel;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tauri::{AppHandle, Emitter};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    pub id: String,
    pub kind: String,
    pub text: String,
    pub created_at: f64,
    #[serde(default)]
    pub is_pinned: bool,
}

pub fn classify(text: &str) -> &'static str {
    let trimmed = text.trim();
    if trimmed.starts_with("http://") || trimmed.starts_with("https://") {
        if !trimmed.contains(char::is_whitespace) {
            return "url";
        }
    }
    if trimmed.len() == 7 && trimmed.starts_with('#') && trimmed[1..].chars().all(|c| c.is_ascii_hexdigit())
    {
        return "color";
    }
    "text"
}

fn store_path() -> std::path::PathBuf {
    crate::settings::support_dir().join("clipboard.json")
}

pub fn load() -> Vec<Entry> {
    std::fs::read_to_string(store_path())
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok())
        .unwrap_or_default()
}

fn save(entries: &[Entry]) {
    if let Ok(text) = serde_json::to_string(entries) {
        let _ = std::fs::write(store_path(), text);
    }
}

/// Adds an entry, promoting a repeat rather than stacking duplicates, and trims to the
/// configured limit while keeping pinned entries.
pub fn insert(entries: &mut Vec<Entry>, text: String, limit: usize) -> bool {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return false;
    }
    if let Some(index) = entries.iter().position(|entry| entry.text == text) {
        let mut existing = entries.remove(index);
        existing.created_at = now_seconds();
        entries.insert(0, existing);
        return true;
    }
    entries.insert(
        0,
        Entry {
            id: format!("{:x}", fxhash(&text)),
            kind: classify(&text).into(),
            text,
            created_at: now_seconds(),
            is_pinned: false,
        },
    );
    trim(entries, limit);
    true
}

pub fn trim(entries: &mut Vec<Entry>, limit: usize) {
    let limit = limit.max(20);
    if entries.len() <= limit {
        return;
    }
    let pinned: Vec<Entry> = entries.iter().filter(|entry| entry.is_pinned).cloned().collect();
    let mut unpinned: Vec<Entry> = entries.iter().filter(|entry| !entry.is_pinned).cloned().collect();
    let room = limit.saturating_sub(pinned.len());
    unpinned.truncate(room);
    let mut merged = pinned;
    merged.extend(unpinned);
    merged.sort_by(|a, b| {
        b.is_pinned
            .cmp(&a.is_pinned)
            .then(b.created_at.partial_cmp(&a.created_at).unwrap_or(std::cmp::Ordering::Equal))
    });
    *entries = merged;
}

fn now_seconds() -> f64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn fxhash(text: &str) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in text.as_bytes() {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

pub struct Watcher {
    stop: Arc<AtomicBool>,
}

impl Watcher {
    /// Polls the clipboard. There is no cross-platform change notification, and the
    /// poll is cheap enough that the alternative isn't worth two platform paths.
    pub fn spawn(app: AppHandle) -> Self {
        let stop = Arc::new(AtomicBool::new(false));
        let flag = stop.clone();
        std::thread::spawn(move || {
            let mut last = String::new();
            while !flag.load(Ordering::Relaxed) {
                std::thread::sleep(std::time::Duration::from_millis(600));
                let Ok(mut board) = arboard::Clipboard::new() else { continue };
                let Ok(text) = board.get_text() else { continue };
                if text == last || text.trim().is_empty() {
                    continue;
                }
                last = text.clone();

                let limit = panel::with_state(&app, |state| state.settings.clipboard_history_limit)
                    .unwrap_or(120);
                let changed = panel::with_state(&app, |state| {
                    insert(&mut state.clipboard, text.clone(), limit)
                })
                .unwrap_or(false);
                if !changed {
                    continue;
                }
                if let Some(entries) = panel::with_state(&app, |state| state.clipboard.clone()) {
                    save(&entries);
                    let _ = app.emit("clipboard", &entries);
                }
            }
        });
        Self { stop }
    }
}

impl Drop for Watcher {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

pub fn history(app: &AppHandle, limit: usize) -> Value {
    let entries = panel::with_state(app, |state| state.clipboard.clone()).unwrap_or_default();
    json!(entries.into_iter().take(limit).collect::<Vec<_>>())
}

pub fn write(app: &AppHandle, text: &str) {
    if let Ok(mut board) = arboard::Clipboard::new() {
        let _ = board.set_text(text.to_string());
    }
    let _ = app;
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(text: &str, pinned: bool) -> Entry {
        Entry {
            id: text.into(),
            kind: "text".into(),
            text: text.into(),
            created_at: 0.0,
            is_pinned: pinned,
        }
    }

    #[test]
    fn classifies_urls_colors_and_text() {
        assert_eq!(classify("https://example.com"), "url");
        assert_eq!(classify("#FF8800"), "color");
        assert_eq!(classify("just some text"), "text");
        // A sentence containing a link is still text.
        assert_eq!(classify("https://a.com and more"), "text");
    }

    #[test]
    fn a_repeat_copy_is_promoted_rather_than_duplicated() {
        let mut entries = vec![entry("a", false), entry("b", false)];
        insert(&mut entries, "b".into(), 120);
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].text, "b");
    }

    #[test]
    fn whitespace_is_never_recorded() {
        let mut entries = Vec::new();
        assert!(!insert(&mut entries, "   \n ".into(), 120));
        assert!(entries.is_empty());
    }

    #[test]
    fn trimming_keeps_pinned_entries() {
        let mut entries: Vec<Entry> = (0..30).map(|i| entry(&format!("e{i}"), i < 3)).collect();
        trim(&mut entries, 20);
        assert_eq!(entries.len(), 20);
        assert_eq!(entries.iter().filter(|e| e.is_pinned).count(), 3);
    }

    #[test]
    fn the_limit_never_drops_below_a_usable_history() {
        let mut entries: Vec<Entry> = (0..40).map(|i| entry(&format!("e{i}"), false)).collect();
        trim(&mut entries, 1);
        assert_eq!(entries.len(), 20);
    }
}

//! The installed-application index behind the Quick Launcher.
//!
//! macOS keeps apps as `.app` bundles in a handful of well-known directories; Windows
//! keeps `.lnk` shortcuts in the Start Menu. Both reduce to "name plus something the
//! OS knows how to open", which is all the launcher needs.

use serde::Serialize;
use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct App {
    pub id: String,
    pub name: String,
    pub path: PathBuf,
    /// Lowercased name and initials, precomputed so search stays allocation-free.
    #[serde(skip)]
    pub search_key: String,
    #[serde(skip)]
    pub initials: String,
}

impl App {
    fn new(name: String, path: PathBuf) -> Self {
        let initials = name
            .split([' ', '-', '_'])
            .filter_map(|word| word.chars().next())
            .collect::<String>()
            .to_lowercase();
        Self {
            id: path.to_string_lossy().to_string(),
            search_key: name.to_lowercase(),
            initials,
            name,
            path,
        }
    }
}

#[cfg(target_os = "macos")]
fn roots() -> Vec<PathBuf> {
    let home = std::env::var("HOME").unwrap_or_default();
    vec![
        PathBuf::from("/Applications"),
        PathBuf::from("/Applications/Utilities"),
        PathBuf::from("/System/Applications"),
        PathBuf::from("/System/Applications/Utilities"),
        PathBuf::from(format!("{home}/Applications")),
    ]
}

#[cfg(target_os = "windows")]
fn roots() -> Vec<PathBuf> {
    let mut roots = Vec::new();
    if let Ok(appdata) = std::env::var("APPDATA") {
        roots.push(PathBuf::from(appdata).join("Microsoft/Windows/Start Menu/Programs"));
    }
    if let Ok(program_data) = std::env::var("ProgramData") {
        roots.push(PathBuf::from(program_data).join("Microsoft/Windows/Start Menu/Programs"));
    }
    roots
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
fn roots() -> Vec<PathBuf> {
    Vec::new()
}

#[cfg(target_os = "macos")]
const APP_EXTENSION: &str = "app";
#[cfg(not(target_os = "macos"))]
const APP_EXTENSION: &str = "lnk";

pub fn scan() -> Vec<App> {
    let mut found: std::collections::BTreeMap<String, App> = Default::default();
    for root in roots() {
        collect(&root, 0, &mut found);
    }
    found.into_values().collect()
}

fn collect(dir: &std::path::Path, depth: usize, out: &mut std::collections::BTreeMap<String, App>) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        let is_app = path
            .extension()
            .and_then(|ext| ext.to_str())
            .map(|ext| ext.eq_ignore_ascii_case(APP_EXTENSION))
            .unwrap_or(false);
        if is_app {
            if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                let app = App::new(stem.to_string(), path.clone());
                out.insert(app.name.to_lowercase(), app);
            }
            continue;
        }
        // Start Menu nests by publisher; don't descend forever.
        if depth < 2 && path.is_dir() {
            collect(&path, depth + 1, out);
        }
    }
}

/// Subsequence match with a light relevance score: prefix beats word-start beats
/// scattered match, so typing "saf" surfaces Safari rather than "Set Alarm Fast".
pub fn rank<'a>(query: &str, apps: &'a [App], limit: usize) -> Vec<&'a App> {
    let needle = query.trim().to_lowercase();
    if needle.is_empty() {
        return Vec::new();
    }
    let mut scored: Vec<(&App, i64)> = apps
        .iter()
        .filter_map(|app| score(&needle, app).map(|value| (app, value)))
        .collect();
    scored.sort_by(|a, b| {
        b.1.cmp(&a.1)
            .then_with(|| a.0.name.len().cmp(&b.0.name.len()))
    });
    scored.into_iter().take(limit).map(|(app, _)| app).collect()
}

fn score(needle: &str, app: &App) -> Option<i64> {
    let haystack = &app.search_key;
    let length = haystack.len() as i64;
    if haystack == needle {
        return Some(1000);
    }
    if haystack.starts_with(needle) {
        return Some(800 - length);
    }
    if app.initials.starts_with(needle) {
        return Some(700);
    }
    if let Some(index) = haystack.find(needle) {
        let word_start = index == 0 || haystack.as_bytes()[index - 1] == b' ';
        return Some(if word_start { 600 } else { 400 } - length);
    }
    // Fall back to a scattered subsequence match.
    let mut characters = haystack.chars();
    for wanted in needle.chars() {
        characters.find(|c| *c == wanted)?;
    }
    Some(200 - length)
}

pub fn launch(path: &std::path::Path) -> Result<(), String> {
    tauri_plugin_opener::open_path(path.to_string_lossy().to_string(), None::<&str>)
        .map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn app(name: &str) -> App {
        App::new(name.into(), PathBuf::from(format!("/Applications/{name}.app")))
    }

    fn names(query: &str, apps: &[App]) -> Vec<String> {
        rank(query, apps, 8).into_iter().map(|a| a.name.clone()).collect()
    }

    fn sample() -> Vec<App> {
        ["Safari", "System Settings", "Sublime Text", "Visual Studio Code",
         "Activity Monitor", "Mail", "Music", "Terminal", "Notes"]
            .iter()
            .map(|name| app(name))
            .collect()
    }

    #[test]
    fn prefix_matches_outrank_scattered_ones() {
        assert_eq!(names("saf", &sample())[0], "Safari");
        assert_eq!(names("term", &sample())[0], "Terminal");
    }

    #[test]
    fn initials_match_multi_word_names() {
        assert_eq!(names("vsc", &sample())[0], "Visual Studio Code");
        assert_eq!(names("am", &sample())[0], "Activity Monitor");
    }

    #[test]
    fn exact_name_wins_over_a_longer_prefix_match() {
        assert_eq!(names("mail", &sample())[0], "Mail");
    }

    #[test]
    fn search_ignores_case_and_surrounding_space() {
        assert_eq!(names("  SAFARI ", &sample()), vec!["Safari"]);
    }

    #[test]
    fn an_empty_or_unmatched_query_returns_nothing() {
        assert!(names("", &sample()).is_empty());
        assert!(names("   ", &sample()).is_empty());
        assert!(names("zzzz", &sample()).is_empty());
    }

    #[test]
    fn a_scattered_subsequence_still_matches() {
        assert!(names("vsl", &sample()).contains(&"Visual Studio Code".to_string()));
    }

    #[test]
    fn the_limit_is_respected() {
        assert!(rank("s", &sample(), 2).len() <= 2);
    }
}

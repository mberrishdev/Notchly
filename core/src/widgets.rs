//! Custom widgets: folders the user drops into the widgets directory.
//!
//! A widget is a `widget.json` manifest plus an HTML entry point. It is loaded into an
//! iframe under its own `widget://<id>/` origin, which is what keeps one widget from
//! reading another's storage or reaching into the host page.

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

/// Permissions a widget can request. The ones the user must approve by hand are
/// listed by `requires_explicit_grant` — the single source of truth, read by
/// enforcement, the settings toggles, and the widget's lock badge alike.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Permission {
    Network,
    Shell,
    System,
    Clipboard,
    Notifications,
}

impl Permission {
    pub fn requires_explicit_grant(self) -> bool {
        matches!(self, Permission::Network | Permission::Shell | Permission::Clipboard)
    }

    pub fn label(self) -> &'static str {
        match self {
            Permission::Network => "Network access",
            Permission::Shell => "Run shell commands",
            Permission::System => "Read system stats",
            Permission::Clipboard => "Read clipboard history",
            Permission::Notifications => "Post notifications",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SettingField {
    pub key: String,
    pub label: String,
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(default)]
    pub help: Option<String>,
    #[serde(default, rename = "default")]
    pub default_value: Option<serde_json::Value>,
    #[serde(default)]
    pub options: Option<Vec<String>>,
    #[serde(default)]
    pub minimum: Option<f64>,
    #[serde(default)]
    pub maximum: Option<f64>,
}

impl SettingField {
    /// A `secret` field is a credential, not a preference: it is kept in the OS
    /// credential store and never written to `settings.json`.
    pub fn is_secret(&self) -> bool {
        self.kind == "secret"
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Manifest {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub version: Option<String>,
    #[serde(default)]
    pub author: Option<String>,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub entry: Option<String>,
    #[serde(default)]
    pub icon: Option<String>,
    #[serde(default)]
    pub height: Option<f64>,
    #[serde(default)]
    pub min_height: Option<f64>,
    #[serde(default)]
    pub max_height: Option<f64>,
    #[serde(default)]
    pub permissions: Option<Vec<Permission>>,
    /// Seconds between automatic reloads; 0 or absent means never.
    #[serde(default)]
    pub refresh_interval: Option<f64>,
    #[serde(default)]
    pub settings: Option<Vec<SettingField>>,
}

impl Manifest {
    pub fn entry_file(&self) -> &str {
        self.entry.as_deref().unwrap_or("index.html")
    }

    /// Declared setting keys that hold credentials rather than preferences.
    pub fn secret_keys(&self) -> Vec<String> {
        self.settings
            .iter()
            .flatten()
            .filter(|field| field.is_secret())
            .map(|field| field.key.clone())
            .collect()
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Package {
    pub manifest: Manifest,
    pub folder: PathBuf,
    /// Bumped whenever files change on disk, which forces the iframe to reload.
    pub revision: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LoadFailure {
    pub folder: PathBuf,
    pub reason: String,
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Catalog {
    pub packages: Vec<Package>,
    pub failures: Vec<LoadFailure>,
}

impl Catalog {
    pub fn package(&self, id: &str) -> Option<&Package> {
        self.packages.iter().find(|p| p.manifest.id == id)
    }

    /// The folder a widget's files live in, looked up by the id it declares.
    pub fn folder_for(&self, id: &str) -> Option<PathBuf> {
        self.package(id).map(|package| package.folder.clone())
    }
}

/// Scans the widgets directory. Folders that look like widgets but can't be loaded are
/// reported rather than skipped, so an author sees why nothing appeared.
pub fn scan(root: &Path, revisions: &std::collections::HashMap<String, u64>) -> Catalog {
    let mut catalog = Catalog::default();
    let Ok(entries) = std::fs::read_dir(root) else { return catalog };

    let mut folders: Vec<PathBuf> = entries
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| path.is_dir())
        .collect();
    folders.sort();

    for folder in folders {
        let manifest_path = folder.join("widget.json");
        if !manifest_path.exists() {
            catalog.failures.push(LoadFailure {
                folder,
                reason: "No widget.json in this folder.".into(),
            });
            continue;
        }
        let text = match std::fs::read_to_string(&manifest_path) {
            Ok(text) => text,
            Err(error) => {
                catalog.failures.push(LoadFailure { folder, reason: error.to_string() });
                continue;
            }
        };
        let manifest: Manifest = match serde_json::from_str(&text) {
            Ok(manifest) => manifest,
            Err(error) => {
                catalog.failures.push(LoadFailure {
                    folder,
                    reason: format!("widget.json could not be read. {error}"),
                });
                continue;
            }
        };
        if manifest.id.trim().is_empty() {
            catalog.failures.push(LoadFailure {
                folder,
                reason: "widget.json needs a non-empty \"id\".".into(),
            });
            continue;
        }
        if !folder.join(manifest.entry_file()).exists() {
            let reason = format!("Entry file \"{}\" is missing.", manifest.entry_file());
            catalog.failures.push(LoadFailure { folder, reason });
            continue;
        }
        if catalog.package(&manifest.id).is_some() {
            let reason = format!("Another widget already uses the id \"{}\".", manifest.id);
            catalog.failures.push(LoadFailure { folder, reason });
            continue;
        }
        let revision = revisions.get(&manifest.id).copied().unwrap_or(0);
        catalog.packages.push(Package { manifest, folder, revision });
    }
    catalog
}

/// The examples that shipped before the marker recorded names. Every build that wrote a
/// zero-byte marker bundled exactly these, so an old marker means these three were the
/// ones offered — and re-seeding them would resurrect any the user had deleted.
const ORIGINAL_EXAMPLES: [&str; 3] = ["command-strip", "pomodoro", "weather"];

/// The marker's filename. Its *contents* are the names already offered to the user.
const SEEDED_MARKER: &str = ".examples-installed";

/// Examples the user has already been offered, read from the marker.
///
/// `None` is a folder with no marker at all — a fresh install, owed everything. An
/// unparsable marker is the pre-0.6.3 format, which recorded only that seeding had
/// happened, never what was seeded.
fn seeded_names(marker: Option<&str>) -> Vec<String> {
    match marker {
        None => Vec::new(),
        Some(text) => serde_json::from_str::<Vec<String>>(text)
            .unwrap_or_else(|_| ORIGINAL_EXAMPLES.iter().map(|name| (*name).to_string()).collect()),
    }
}

/// Bundled examples the user has never been offered, and so is owed.
fn unseeded(bundled: &[String], seeded: &[String]) -> Vec<String> {
    bundled.iter().filter(|name| !seeded.contains(name)).cloned().collect()
}

/// Directory names of the bundled examples, sorted so the record is stable.
fn bundled_examples(resource_dir: &Path) -> Vec<String> {
    let Ok(entries) = std::fs::read_dir(resource_dir.join("ExampleWidgets")) else {
        return Vec::new();
    };
    let mut names: Vec<String> = entries
        .flatten()
        .filter(|entry| entry.path().is_dir())
        .filter_map(|entry| entry.file_name().into_string().ok())
        .collect();
    names.sort();
    names
}

/// Copies in any bundled example the user has not been offered before.
///
/// Runs on every launch rather than only the first, so an example added in a later
/// release still arrives. The marker records *which* examples have been offered, which
/// is what keeps one the user deleted from coming back the next time the app starts.
pub fn seed_examples(resource_dir: &Path, target: &Path) -> usize {
    let bundled = bundled_examples(resource_dir);
    if bundled.is_empty() {
        return 0;
    }
    let marker = target.join(SEEDED_MARKER);
    let existing = std::fs::read_to_string(&marker).ok();
    let mut seeded = seeded_names(existing.as_deref());

    let source = resource_dir.join("ExampleWidgets");
    let mut copied = 0;
    for name in unseeded(&bundled, &seeded) {
        let destination = target.join(&name);
        // A folder already there is the user's, not ours to overwrite — but it still
        // counts as offered, so we do not try again on the next launch.
        if !destination.exists() && copy_dir(&source.join(&name), &destination).is_ok() {
            copied += 1;
        }
    }

    for name in bundled {
        if !seeded.contains(&name) {
            seeded.push(name);
        }
    }
    seeded.sort();
    if let Ok(text) = serde_json::to_string(&seeded) {
        let _ = std::fs::write(&marker, text);
    }
    copied
}

pub fn copy_examples(resource_dir: &Path, target: &Path, overwrite: bool) -> usize {
    let source = resource_dir.join("ExampleWidgets");
    let Ok(entries) = std::fs::read_dir(&source) else { return 0 };
    let mut copied = 0;
    for entry in entries.flatten() {
        let destination = target.join(entry.file_name());
        if destination.exists() {
            if !overwrite {
                continue;
            }
            let _ = std::fs::remove_dir_all(&destination);
        }
        if copy_dir(&entry.path(), &destination).is_ok() {
            copied += 1;
        }
    }
    copied
}

fn copy_dir(from: &Path, to: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(to)?;
    for entry in std::fs::read_dir(from)? {
        let entry = entry?;
        let target = to.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_dir(&entry.path(), &target)?;
        } else {
            std::fs::copy(entry.path(), target)?;
        }
    }
    Ok(())
}
/// Scaffolds a new widget folder and returns it, ready to open in an editor.
pub fn create_starter(root: &Path, name: &str) -> Result<PathBuf, String> {
    let slug: String = name
        .to_lowercase()
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect();
    let slug = slug.trim_matches('-').to_string();
    let base = if slug.is_empty() { "my-widget".to_string() } else { slug };

    let mut folder = root.join(&base);
    let mut suffix = 2;
    while folder.exists() {
        folder = root.join(format!("{base}-{suffix}"));
        suffix += 1;
    }
    std::fs::create_dir_all(&folder).map_err(|error| error.to_string())?;

    let display_name = if name.trim().is_empty() { "My Widget" } else { name.trim() };
    let manifest = serde_json::json!({
        "id": format!("local.{}", folder.file_name().unwrap_or_default().to_string_lossy()),
        "name": display_name,
        "version": "1.0.0",
        "description": "A custom widget.",
        "entry": "index.html",
        "height": 150,
        "permissions": ["system"],
        "settings": [
            { "key": "greeting", "type": "string", "label": "Greeting", "default": "Hello" }
        ]
    });
    std::fs::write(
        folder.join("widget.json"),
        serde_json::to_string_pretty(&manifest).unwrap_or_default(),
    )
    .map_err(|error| error.to_string())?;
    std::fs::write(folder.join("index.html"), STARTER_HTML).map_err(|error| error.to_string())?;
    Ok(folder)
}

const STARTER_HTML: &str = r#"<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { display: flex; flex-direction: column; gap: 10px; padding: 14px; justify-content: center; }
    h1 { font-size: 20px; font-weight: 600; margin: 0; letter-spacing: -0.02em; }
    p  { margin: 0; color: var(--notchly-text-secondary); }
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
        document.getElementById('cpu').textContent = Math.round(stats.cpu * 100) + '%';
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
"#;

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    /// A fresh directory per test.
    ///
    /// Named from a counter rather than a timestamp: `Instant`'s Debug output contains
    /// colons, which macOS accepts in a filename and Windows does not, so the original
    /// version passed locally and failed every one of these tests on CI.
    fn temp() -> PathBuf {
        use std::sync::atomic::{AtomicUsize, Ordering};
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let unique = std::env::temp_dir()
            .join(format!("notchly-test-{}", std::process::id()))
            .join(NEXT.fetch_add(1, Ordering::Relaxed).to_string());
        std::fs::create_dir_all(&unique).unwrap();
        unique
    }

    fn write_widget(root: &Path, name: &str, manifest: &str, entry: Option<&str>) {
        let folder = root.join(name);
        std::fs::create_dir_all(&folder).unwrap();
        std::fs::write(folder.join("widget.json"), manifest).unwrap();
        if let Some(entry) = entry {
            std::fs::write(folder.join(entry), "<html></html>").unwrap();
        }
    }

    /// Builds a stand-in for the bundled resource directory.
    fn examples_dir(names: &[&str]) -> PathBuf {
        let resources = temp();
        let source = resources.join("ExampleWidgets");
        for name in names {
            write_widget(&source, name, r#"{ "id": "x", "name": "X" }"#, Some("index.html"));
        }
        resources
    }

    #[test]
    fn a_folder_with_no_marker_is_owed_everything() {
        assert!(seeded_names(None).is_empty());
    }

    #[test]
    fn a_zero_byte_marker_means_the_three_originals() {
        assert_eq!(seeded_names(Some("")), ORIGINAL_EXAMPLES.to_vec());
    }

    #[test]
    fn a_recorded_marker_is_read_back() {
        assert_eq!(seeded_names(Some(r#"["a","b"]"#)), vec!["a".to_string(), "b".to_string()]);
    }

    #[test]
    fn only_unoffered_examples_are_owed() {
        let bundled = vec!["a".to_string(), "b".to_string(), "c".to_string()];
        let seeded = vec!["b".to_string()];
        assert_eq!(unseeded(&bundled, &seeded), vec!["a".to_string(), "c".to_string()]);
    }

    #[test]
    fn a_first_launch_seeds_every_example() {
        let resources = examples_dir(&["alpha", "beta"]);
        let widgets = temp();
        assert_eq!(seed_examples(&resources, &widgets), 2);
        assert!(widgets.join("alpha").exists());
        assert!(widgets.join("beta").exists());
    }

    /// The reason the marker exists at all.
    #[test]
    fn a_deleted_example_is_not_resurrected() {
        let resources = examples_dir(&["alpha", "beta"]);
        let widgets = temp();
        seed_examples(&resources, &widgets);
        std::fs::remove_dir_all(widgets.join("alpha")).unwrap();

        assert_eq!(seed_examples(&resources, &widgets), 0);
        assert!(!widgets.join("alpha").exists());
    }

    /// The bug this replaced: a marker said "seeded", so nothing new ever arrived.
    #[test]
    fn an_example_added_in_a_later_release_still_arrives() {
        let widgets = temp();
        seed_examples(&examples_dir(&["alpha"]), &widgets);
        assert!(!widgets.join("beta").exists());

        assert_eq!(seed_examples(&examples_dir(&["alpha", "beta"]), &widgets), 1);
        assert!(widgets.join("beta").exists());
    }

    /// An install predating the recorded marker owns those three already, but is still
    /// owed anything bundled since.
    #[test]
    fn a_legacy_marker_seeds_only_what_came_after_it() {
        let widgets = temp();
        std::fs::write(widgets.join(SEEDED_MARKER), b"").unwrap();
        let resources = examples_dir(&["command-strip", "pomodoro", "weather", "up-next"]);

        assert_eq!(seed_examples(&resources, &widgets), 1);
        assert!(widgets.join("up-next").exists());
        assert!(!widgets.join("weather").exists(), "an original was resurrected");
    }

    #[test]
    fn a_users_own_folder_is_never_overwritten_but_counts_as_offered() {
        let widgets = temp();
        write_widget(&widgets, "alpha", r#"{ "id": "mine", "name": "Mine" }"#, Some("index.html"));
        let resources = examples_dir(&["alpha"]);

        assert_eq!(seed_examples(&resources, &widgets), 0);
        let manifest = std::fs::read_to_string(widgets.join("alpha/widget.json")).unwrap();
        assert!(manifest.contains("mine"), "the user's own widget was overwritten");
    }

    /// The examples are copied into the user's folder on first launch, so a typo in one
    /// of them is a broken widget for everybody rather than a broken test for us.
    #[test]
    fn every_bundled_example_scans_without_failures() {
        let examples = Path::new(env!("CARGO_MANIFEST_DIR")).join("resources/ExampleWidgets");
        let catalog = scan(&examples, &HashMap::new());
        assert!(catalog.failures.is_empty(), "{:?}", catalog.failures);
        assert!(
            catalog.packages.len() >= 4,
            "expected the bundled examples, found {}",
            catalog.packages.len()
        );
        for package in &catalog.packages {
            assert!(!package.manifest.id.is_empty());
            assert!(!package.manifest.name.is_empty());
        }
    }

    #[test]
    fn a_secret_field_is_named_as_one() {
        let root = temp();
        write_widget(
            &root,
            "a",
            r#"{ "id": "a.b", "name": "T", "settings": [
                 { "key": "token", "label": "Token", "type": "secret" },
                 { "key": "city", "label": "City", "type": "string" } ] }"#,
            Some("index.html"),
        );
        let catalog = scan(&root, &HashMap::new());
        let manifest = &catalog.packages[0].manifest;
        assert_eq!(manifest.secret_keys(), vec!["token".to_string()]);
    }

    #[test]
    fn a_manifest_without_secrets_names_none() {
        let root = temp();
        write_widget(&root, "a", r#"{ "id": "a.b", "name": "T" }"#, Some("index.html"));
        let catalog = scan(&root, &HashMap::new());
        assert!(catalog.packages[0].manifest.secret_keys().is_empty());
    }

    #[test]
    fn minimal_manifest_loads_and_defaults_the_entry_file() {
        let root = temp();
        write_widget(&root, "a", r#"{ "id": "a.b", "name": "Thing" }"#, Some("index.html"));
        let catalog = scan(&root, &HashMap::new());
        assert_eq!(catalog.packages.len(), 1);
        assert_eq!(catalog.packages[0].manifest.entry_file(), "index.html");
        assert!(catalog.failures.is_empty());
    }

    #[test]
    fn a_missing_entry_file_is_reported_rather_than_skipped() {
        let root = temp();
        write_widget(&root, "a", r#"{ "id": "a.b", "name": "T", "entry": "main.html" }"#, None);
        let catalog = scan(&root, &HashMap::new());
        assert!(catalog.packages.is_empty());
        assert!(catalog.failures[0].reason.contains("main.html"));
    }

    #[test]
    fn a_duplicate_id_is_reported_rather_than_shadowing() {
        let root = temp();
        write_widget(&root, "a", r#"{ "id": "same", "name": "A" }"#, Some("index.html"));
        write_widget(&root, "b", r#"{ "id": "same", "name": "B" }"#, Some("index.html"));
        let catalog = scan(&root, &HashMap::new());
        assert_eq!(catalog.packages.len(), 1);
        assert!(catalog.failures[0].reason.contains("already uses the id"));
    }

    #[test]
    fn a_folder_without_a_manifest_is_reported() {
        let root = temp();
        std::fs::create_dir_all(root.join("not-a-widget")).unwrap();
        let catalog = scan(&root, &HashMap::new());
        assert!(catalog.failures[0].reason.contains("No widget.json"));
    }

    #[test]
    fn broken_json_names_the_problem() {
        let root = temp();
        write_widget(&root, "a", "{ not json", Some("index.html"));
        let catalog = scan(&root, &HashMap::new());
        assert!(catalog.failures[0].reason.contains("could not be read"));
    }

    #[test]
    fn an_unknown_permission_is_rejected_rather_than_ignored() {
        // Better to show the author a load error than to run with a permission they
        // think they asked for.
        let root = temp();
        write_widget(
            &root,
            "a",
            r#"{ "id": "a", "name": "b", "permissions": ["root"] }"#,
            Some("index.html"),
        );
        assert!(scan(&root, &HashMap::new()).packages.is_empty());
    }

    #[test]
    fn full_manifest_decodes_permissions_and_settings() {
        let root = temp();
        write_widget(
            &root,
            "a",
            r#"{ "id": "a", "name": "T", "permissions": ["network", "shell"],
                 "settings": [{ "key": "city", "label": "City", "type": "string", "default": "Berlin" }] }"#,
            Some("index.html"),
        );
        let catalog = scan(&root, &HashMap::new());
        let manifest = &catalog.packages[0].manifest;
        assert_eq!(manifest.permissions.as_ref().unwrap().len(), 2);
        assert_eq!(manifest.settings.as_ref().unwrap()[0].key, "city");
    }

    #[test]
    fn sensitive_permissions_require_an_explicit_grant() {
        for permission in [Permission::Shell, Permission::Clipboard, Permission::Network] {
            assert!(permission.requires_explicit_grant(), "{permission:?}");
        }
        for permission in [Permission::System, Permission::Notifications] {
            assert!(!permission.requires_explicit_grant(), "{permission:?}");
        }
    }
}

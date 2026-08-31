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

/// Copies the bundled starter widgets in on first launch, so the folder is never an
/// empty void the user has to guess at.
pub fn seed_examples(resource_dir: &Path, target: &Path) -> usize {
    let marker = target.join(".examples-installed");
    if marker.exists() {
        return 0;
    }
    let copied = copy_examples(resource_dir, target, false);
    let _ = std::fs::write(marker, b"");
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn temp() -> PathBuf {
        let dir = std::env::temp_dir().join(format!("notchly-test-{}", std::process::id()));
        let unique = dir.join(format!("{:?}", std::time::Instant::now()));
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

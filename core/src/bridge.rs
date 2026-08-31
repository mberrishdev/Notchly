//! The Rust half of `window.notchly`.
//!
//! Two rules from CONTEXT.md are enforced here rather than documented and hoped for:
//! a permission the widget didn't declare — or the user didn't grant — rejects with a
//! message naming the switch to flip, and it never returns empty data instead.

use crate::panel;
use crate::services::metrics::Sampler;
use crate::settings::{Settings, WidgetKind};
use crate::widgets::Permission;
use serde_json::{json, Value};
use std::path::PathBuf;
use tauri::{AppHandle, Manager};

pub struct Denied(pub String);

impl From<Denied> for String {
    fn from(value: Denied) -> Self {
        value.0
    }
}

fn storage_path(widget_id: &str) -> PathBuf {
    let dir = crate::settings::support_dir().join("WidgetStorage");
    let _ = std::fs::create_dir_all(&dir);
    // Widget ids are user-authored; keep them from becoming path segments.
    let safe: String = widget_id
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_' { c } else { '_' })
        .collect();
    dir.join(format!("{safe}.json"))
}

fn read_storage(widget_id: &str) -> serde_json::Map<String, Value> {
    std::fs::read_to_string(storage_path(widget_id))
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok())
        .unwrap_or_default()
}

fn write_storage(widget_id: &str, data: &serde_json::Map<String, Value>) {
    if let Ok(text) = serde_json::to_string_pretty(data) {
        let _ = std::fs::write(storage_path(widget_id), text);
    }
}

/// A widget's declared settings: schema defaults, overlaid with what the user chose.
pub fn widget_settings(app: &AppHandle, widget_id: &str) -> serde_json::Map<String, Value> {
    let mut values = serde_json::Map::new();
    if let Some(catalog) = panel::with_state(app, |state| state.catalog.clone()) {
        if let Some(package) = catalog.package(widget_id) {
            for field in package.manifest.settings.iter().flatten() {
                if let Some(default) = &field.default_value {
                    values.insert(field.key.clone(), default.clone());
                }
            }
        }
    }
    if let Some(preferences) = panel::with_state(app, |state| {
        state
            .settings
            .slots
            .iter()
            .find(|slot| slot.widget_id == widget_id)
            .map(|slot| slot.preferences.clone())
    })
    .flatten()
    {
        for (key, value) in preferences {
            values.insert(key, value);
        }
    }
    values
}

fn granted(settings: &Settings, widget_id: &str, permission: Permission) -> bool {
    let list = match permission {
        Permission::Shell => &settings.shell_approved_widgets,
        Permission::Network => &settings.network_approved_widgets,
        Permission::Clipboard => &settings.clipboard_approved_widgets,
        _ => return true,
    };
    list.iter().any(|id| id == widget_id)
}

/// Built-in widgets are part of the app, not sandboxed content, so they are not
/// subject to the manifest permission checks that gate custom widgets.
fn is_builtin(widget_id: &str) -> bool {
    matches!(widget_id, "clock" | "media" | "system" | "launcher" | "clipboard")
}

fn require(app: &AppHandle, widget_id: &str, permission: Permission) -> Result<(), Denied> {
    if is_builtin(widget_id) {
        return Ok(());
    }
    let declared = panel::with_state(app, |state| {
        state
            .catalog
            .package(widget_id)
            .map(|package| {
                package
                    .manifest
                    .permissions
                    .as_ref()
                    .map(|list| list.contains(&permission))
                    .unwrap_or(false)
            })
            .unwrap_or(false)
    })
    .unwrap_or(false);

    if !declared {
        return Err(Denied(format!(
            "This widget didn't ask for \"{}\" in its widget.json.",
            permission.label()
        )));
    }
    if !permission.requires_explicit_grant() {
        return Ok(());
    }
    let allowed = panel::with_state(app, |state| granted(&state.settings, widget_id, permission))
        .unwrap_or(false);
    if allowed {
        Ok(())
    } else {
        Err(Denied(format!(
            "This widget hasn't been granted \"{}\". Enable it in Notchly ▸ Settings ▸ Widgets.",
            permission.label()
        )))
    }
}

pub fn theme_payload(settings: &Settings) -> Value {
    json!({
        "accent": settings.accent_hex,
        "text": "rgba(255,255,255,0.92)",
        "text-secondary": "rgba(255,255,255,0.56)",
        "text-tertiary": "rgba(255,255,255,0.34)",
        "surface": "rgba(255,255,255,0.06)",
        "surface-hover": "rgba(255,255,255,0.10)",
        "hairline": "rgba(255,255,255,0.10)",
        "radius": "12px",
        "appearance": "dark",
        "font": "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif"
    })
}

/// Dispatches one `window.notchly` call.
pub async fn dispatch(
    app: AppHandle,
    widget_id: String,
    method: String,
    params: Value,
) -> Result<Value, String> {
    let param = |key: &str| params.get(key).cloned().unwrap_or(Value::Null);
    let string = |key: &str| param(key).as_str().map(str::to_string);

    match method.as_str() {
        "system.stats" => {
            require(&app, &widget_id, Permission::System)?;
            let sample = panel::with_state(&app, |state| state.last_metrics.clone()).flatten();
            match sample {
                Some(sample) => Ok(serde_json::to_value(sample).unwrap_or(Value::Null)),
                None => {
                    // Nothing is sampling yet, so take one reading rather than lying.
                    let sample = tauri::async_runtime::spawn_blocking(|| {
                        let mut sampler = Sampler::new();
                        let _ = sampler.sample(false);
                        std::thread::sleep(std::time::Duration::from_millis(220));
                        sampler.sample(false)
                    })
                    .await
                    .map_err(|error| error.to_string())?;
                    Ok(serde_json::to_value(sample).unwrap_or(Value::Null))
                }
            }
        }

        "system.info" => Ok(json!({
            "hostName": sysinfo::System::host_name().unwrap_or_default(),
            "userName": std::env::var("USER").or_else(|_| std::env::var("USERNAME")).unwrap_or_default(),
            "osVersion": sysinfo::System::long_os_version().unwrap_or_default(),
            "appearance": "dark",
        })),

        "storage.get" => {
            let key = string("key").ok_or_else(|| "storage.get needs a key.".to_string())?;
            Ok(read_storage(&widget_id).get(&key).cloned().unwrap_or(Value::Null))
        }
        "storage.set" => {
            let key = string("key").ok_or_else(|| "storage.set needs a key.".to_string())?;
            let mut data = read_storage(&widget_id);
            data.insert(key, param("value"));
            write_storage(&widget_id, &data);
            Ok(json!(true))
        }
        "storage.remove" => {
            let key = string("key").ok_or_else(|| "storage.remove needs a key.".to_string())?;
            let mut data = read_storage(&widget_id);
            data.remove(&key);
            write_storage(&widget_id, &data);
            Ok(json!(true))
        }
        "storage.keys" => {
            let mut keys: Vec<String> = read_storage(&widget_id).keys().cloned().collect();
            keys.sort();
            Ok(json!(keys))
        }
        "storage.clear" => {
            write_storage(&widget_id, &serde_json::Map::new());
            Ok(json!(true))
        }

        "settings.get" => {
            let key = string("key").ok_or_else(|| "settings.get needs a key.".to_string())?;
            Ok(widget_settings(&app, &widget_id).get(&key).cloned().unwrap_or(Value::Null))
        }
        "settings.all" => Ok(Value::Object(widget_settings(&app, &widget_id))),

        "media.now" => Ok(crate::services::media::now_playing()),
        "media.playPause" => {
            crate::services::media::transport("playpause");
            Ok(json!(true))
        }
        "media.next" => {
            crate::services::media::transport("next track");
            Ok(json!(true))
        }
        "media.previous" => {
            crate::services::media::transport("previous track");
            Ok(json!(true))
        }

        "clipboard.history" => {
            require(&app, &widget_id, Permission::Clipboard)?;
            let limit = param("limit").as_u64().unwrap_or(20) as usize;
            Ok(crate::services::clipboard::history(&app, limit))
        }
        "clipboard.write" => {
            let text = string("text").ok_or_else(|| "clipboard.write needs text.".to_string())?;
            crate::services::clipboard::write(&app, &text);
            Ok(json!(true))
        }

        "shell.run" => {
            require(&app, &widget_id, Permission::Shell)?;
            let command = string("command").filter(|c| !c.is_empty())
                .ok_or_else(|| "shell.run needs a command.".to_string())?;
            let timeout = param("timeout").as_f64().unwrap_or(10.0).clamp(0.5, 60.0);
            tauri::async_runtime::spawn_blocking(move || run_shell(&command, timeout))
                .await
                .map_err(|error| error.to_string())
        }

        "http.get" => {
            require(&app, &widget_id, Permission::Network)?;
            let url = string("url").ok_or_else(|| "http.get needs a url.".to_string())?;
            if !(url.starts_with("https://") || url.starts_with("http://")) {
                return Err("http.get needs an http(s) url.".into());
            }
            let response = reqwest::get(&url).await.map_err(|error| error.to_string())?;
            let status = response.status().as_u16();
            let body = response.text().await.map_err(|error| error.to_string())?;
            Ok(json!({ "status": status, "body": body }))
        }

        "open.url" => {
            let url = string("url").ok_or_else(|| "open.url needs a url.".to_string())?;
            let allowed = ["http://", "https://", "mailto:", "file://"];
            if !allowed.iter().any(|scheme| url.starts_with(scheme)) {
                return Err("Only http, https, mailto and file URLs can be opened.".into());
            }
            tauri_plugin_opener::open_url(url, None::<&str>).map_err(|error| error.to_string())?;
            Ok(json!(true))
        }

        "notify" => {
            require(&app, &widget_id, Permission::Notifications)?;
            let title = string("title").unwrap_or_else(|| "Notchly".into());
            let body = string("body").unwrap_or_default();
            crate::services::notify::post(&title, &body);
            Ok(json!(true))
        }

        "ui.theme" => {
            let settings = panel::with_state(&app, |state| state.settings.clone()).unwrap_or_default();
            Ok(theme_payload(&settings))
        }
        "ui.close" => {
            panel::close(&app);
            Ok(json!(true))
        }
        "ui.holdOpen" => {
            let hold = param("value").as_bool().unwrap_or(true);
            panel::set_hold_open(&app, &format!("web:{widget_id}"), hold);
            Ok(json!(true))
        }
        // Height is applied by the host page, which owns the iframe.
        "ui.resize" => Ok(json!(true)),

        "log" => {
            let message = string("message").unwrap_or_default();
            panel::append_widget_log(&app, &widget_id, &message);
            Ok(json!(true))
        }

        other => Err(format!("Unknown method \"{other}\".")),
    }
}

fn run_shell(command: &str, timeout: f64) -> Value {
    use std::process::{Command, Stdio};

    #[cfg(target_os = "windows")]
    let mut child = match Command::new("cmd")
        .args(["/C", command])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(error) => return json!({ "code": -1, "stdout": "", "stderr": error.to_string() }),
    };

    #[cfg(not(target_os = "windows"))]
    let mut child = match Command::new("/bin/sh")
        .args(["-lc", command])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(error) => return json!({ "code": -1, "stdout": "", "stderr": error.to_string() }),
    };

    // A command that never exits must not wedge the widget forever.
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs_f64(timeout);
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if std::time::Instant::now() < deadline => {
                std::thread::sleep(std::time::Duration::from_millis(25));
            }
            Ok(None) => {
                let _ = child.kill();
                break;
            }
            Err(error) => return json!({ "code": -1, "stdout": "", "stderr": error.to_string() }),
        }
    }
    match child.wait_with_output() {
        Ok(output) => json!({
            "code": output.status.code().unwrap_or(-1),
            "stdout": String::from_utf8_lossy(&output.stdout),
            "stderr": String::from_utf8_lossy(&output.stderr),
        }),
        Err(error) => json!({ "code": -1, "stdout": "", "stderr": error.to_string() }),
    }
}

/// Which widget kinds can reach the bridge at all.
pub fn is_web_widget(app: &AppHandle, widget_id: &str) -> bool {
    panel::with_state(app, |state| {
        state
            .settings
            .slots
            .iter()
            .any(|slot| slot.widget_id == widget_id && slot.kind == WidgetKind::Web)
    })
    .unwrap_or(false)
}

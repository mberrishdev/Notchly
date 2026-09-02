//! The Rust half of `window.notchly`.
//!
//! Two rules from CONTEXT.md are enforced here rather than documented and hoped for:
//! a permission the widget didn't declare — or the user didn't grant — rejects with a
//! message naming the switch to flip, and it never returns empty data instead.

use crate::panel;
use crate::services::metrics::Sampler;
use crate::settings::Settings;
use crate::widgets::Permission;
use serde_json::{json, Value};
use std::path::PathBuf;
use tauri::AppHandle;

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
    let mut secret_keys: Vec<String> = Vec::new();
    if let Some(catalog) = panel::with_state(app, |state| state.catalog.clone()) {
        if let Some(package) = catalog.package(widget_id) {
            secret_keys = package.manifest.secret_keys();
            for field in package.manifest.settings.iter().flatten() {
                // A secret has no default worth carrying: it is either filed or absent.
                if field.is_secret() {
                    continue;
                }
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
            // Refuse a secret's value from settings.json even if one is somehow there —
            // a widget that changed a field from `string` to `secret` would otherwise go
            // on reading the plaintext copy the user thought they had replaced.
            if secret_keys.contains(&key) {
                continue;
            }
            values.insert(key, value);
        }
    }
    // The widget's own credentials, from the OS store. Widgets are isolated by id, so
    // this only ever hands a secret back to the widget that owns it.
    for key in secret_keys {
        if let Some(secret) = crate::secrets::get(widget_id, &key) {
            values.insert(key, Value::String(secret));
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

/// What Notchly calls itself when a widget makes a request.
///
/// Identifying the app rather than the widget is deliberate: the host is what a server
/// would rate limit or block, and a widget cannot be trusted to name itself honestly.
fn user_agent(version: &str) -> String {
    format!("Notchly/{version}")
}

/// Header names a widget may not set. These describe the connection rather than the
/// request, so letting a widget forge them would misdescribe a hop it does not own.
/// Everything else — `Authorization` above all — is the widget's to send.
const REFUSED_HEADERS: [&str; 6] = [
    "connection",
    "host",
    "proxy-authorization",
    "proxy-connection",
    "transfer-encoding",
    "upgrade",
];

/// Methods a widget may use. `CONNECT` and `TRACE` are refused: neither has a meaning
/// worth handing to a widget, and both are the usual ingredients of a proxy trick.
fn http_method(name: Option<&str>) -> Result<reqwest::Method, String> {
    let Some(name) = name else {
        return Ok(reqwest::Method::GET);
    };
    match name.to_ascii_uppercase().as_str() {
        "GET" => Ok(reqwest::Method::GET),
        "HEAD" => Ok(reqwest::Method::HEAD),
        "POST" => Ok(reqwest::Method::POST),
        "PUT" => Ok(reqwest::Method::PUT),
        "PATCH" => Ok(reqwest::Method::PATCH),
        "DELETE" => Ok(reqwest::Method::DELETE),
        other => Err(format!("http does not allow the {other} method.")),
    }
}

/// Flattens the `headers` object into pairs, refusing the ones above.
///
/// A missing or null value is not an error — `http.get(url)` with no headers is the
/// common case. A non-string value is, because silently stringifying `{ Accept: 1 }`
/// would send something the widget never wrote.
fn header_pairs(value: &Value) -> Result<Vec<(String, String)>, String> {
    let Some(map) = value.as_object() else {
        return match value {
            Value::Null => Ok(Vec::new()),
            _ => Err("http headers must be an object.".into()),
        };
    };
    let mut pairs = Vec::with_capacity(map.len());
    for (name, entry) in map {
        let Some(text) = entry.as_str() else {
            return Err(format!("The {name} header must be a string."));
        };
        if REFUSED_HEADERS.contains(&name.to_ascii_lowercase().as_str()) {
            return Err(format!("Widgets cannot set the {name} header."));
        }
        pairs.push((name.clone(), text.to_string()));
    }
    Ok(pairs)
}

/// The request body, and the content type it implies when the widget named none.
/// A string is sent as written; anything else is JSON, which is what a widget passing
/// an object plainly meant.
fn http_body(value: &Value) -> Option<(String, &'static str)> {
    match value {
        Value::Null => None,
        Value::String(text) => Some((text.clone(), "text/plain; charset=utf-8")),
        other => Some((other.to_string(), "application/json")),
    }
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
            crate::services::media::transport(crate::services::media::Transport::PlayPause);
            Ok(json!(true))
        }
        "media.next" => {
            crate::services::media::transport(crate::services::media::Transport::Next);
            Ok(json!(true))
        }
        "media.previous" => {
            crate::services::media::transport(crate::services::media::Transport::Previous);
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

        // `http.get` is `http.request` with the method fixed, so the two cannot drift.
        "http.get" | "http.request" => {
            require(&app, &widget_id, Permission::Network)?;
            let url = string("url").ok_or_else(|| "http needs a url.".to_string())?;
            if !(url.starts_with("https://") || url.starts_with("http://")) {
                return Err("http needs an http(s) url.".into());
            }
            let verb = match method.as_str() {
                "http.get" => reqwest::Method::GET,
                _ => http_method(string("method").as_deref())?,
            };
            let headers = header_pairs(&param("headers"))?;

            let client = reqwest::Client::builder()
                // reqwest sends no User-Agent unless told to, and some hosts refuse a
                // request without one outright — GitHub answers 403 "Request forbidden
                // by administrative rules", which reads like a credentials problem and
                // is not one. A widget that sets its own still wins: an explicit header
                // overrides the default.
                .user_agent(user_agent(&app.package_info().version.to_string()))
                // A widget cannot cancel its own request, so an unresponsive host would
                // otherwise hold the promise open for the life of the app.
                .timeout(std::time::Duration::from_secs(20))
                .build()
                .map_err(|error| error.to_string())?;
            let mut request = client.request(verb, &url);
            let named_content_type = headers
                .iter()
                .any(|(name, _)| name.eq_ignore_ascii_case("content-type"));
            for (name, value) in headers {
                request = request.header(name, value);
            }
            if let Some((body, content_type)) = http_body(&param("body")) {
                if !named_content_type {
                    request = request.header("content-type", content_type);
                }
                request = request.body(body);
            }

            let response = request.send().await.map_err(|error| error.to_string())?;
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

#[cfg(test)]
mod tests {
    use super::{header_pairs, http_body, http_method, user_agent};
    use serde_json::json;

    #[test]
    fn the_user_agent_names_the_app_and_its_version() {
        assert_eq!(user_agent("0.7.0"), "Notchly/0.7.0");
    }

    #[test]
    fn a_missing_method_is_a_get() {
        assert_eq!(http_method(None).unwrap(), reqwest::Method::GET);
    }

    #[test]
    fn methods_are_matched_regardless_of_case() {
        assert_eq!(http_method(Some("post")).unwrap(), reqwest::Method::POST);
        assert_eq!(http_method(Some("PaTcH")).unwrap(), reqwest::Method::PATCH);
    }

    #[test]
    fn connect_and_trace_are_refused_by_name() {
        for method in ["CONNECT", "TRACE"] {
            let error = http_method(Some(method)).unwrap_err();
            assert!(error.contains(method), "{error}");
        }
    }

    #[test]
    fn absent_headers_are_not_an_error() {
        assert!(header_pairs(&json!(null)).unwrap().is_empty());
    }

    #[test]
    fn authorization_is_passed_through() {
        let pairs = header_pairs(&json!({ "Authorization": "Bearer t" })).unwrap();
        assert_eq!(pairs, vec![("Authorization".into(), "Bearer t".into())]);
    }

    #[test]
    fn connection_headers_are_refused() {
        // Case-insensitively: the refusal must not be dodged by spelling it Host.
        for name in ["connection", "Host", "Transfer-Encoding"] {
            assert!(header_pairs(&json!({ name: "x" })).is_err(), "{name} was allowed");
        }
    }

    #[test]
    fn a_non_string_header_is_rejected_rather_than_stringified() {
        let error = header_pairs(&json!({ "Accept": 1 })).unwrap_err();
        assert!(error.contains("Accept"), "{error}");
    }

    #[test]
    fn headers_must_be_an_object() {
        assert!(header_pairs(&json!("Authorization: Bearer t")).is_err());
    }

    #[test]
    fn a_string_body_is_sent_as_written() {
        let (body, kind) = http_body(&json!("a=1")).unwrap();
        assert_eq!(body, "a=1");
        assert!(kind.starts_with("text/plain"));
    }

    #[test]
    fn an_object_body_becomes_json() {
        let (body, kind) = http_body(&json!({ "a": 1 })).unwrap();
        assert_eq!(body, r#"{"a":1}"#);
        assert_eq!(kind, "application/json");
    }

    #[test]
    fn no_body_means_no_body() {
        assert!(http_body(&json!(null)).is_none());
    }
}

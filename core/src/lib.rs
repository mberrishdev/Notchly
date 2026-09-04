mod bridge;
mod builtins;
mod geometry;
mod hover;
mod panel;
mod platform;
mod services;
mod tray;
mod updates;
mod secrets;
mod widget_protocol;
mod widgets;
mod settings;

use panel::{PanelSnapshot, PanelState, SharedPanel, PANEL_LABEL};
use settings::Settings;
use std::sync::Mutex;
use tauri::{AppHandle, Manager};

static APP: std::sync::OnceLock<AppHandle> = std::sync::OnceLock::new();

/// The running app, for the few services that have no handle of their own.
pub fn app_handle() -> Option<AppHandle> {
    APP.get().cloned()
}

#[tauri::command]
fn get_state(app: AppHandle) -> Option<PanelSnapshot> {
    panel::with_state(&app, |state| state.last_snapshot.clone())?
}

#[tauri::command]
fn app_version(app: AppHandle) -> String {
    updates::current_version(&app)
}

#[tauri::command]
async fn check_update(app: AppHandle) -> updates::UpdateStatus {
    updates::check(app).await
}

#[tauri::command]
async fn install_update(app: AppHandle) -> Result<(), String> {
    updates::install(app).await
}

#[tauri::command]
fn open_panel(app: AppHandle) {
    panel::open(&app)
}

#[tauri::command]
fn close_panel(app: AppHandle) {
    // Closing on purpose must not re-open the moment the watchdog sees the pointer.
    panel::suppress_hover(&app, 500);
    panel::close(&app)
}

#[tauri::command]
fn toggle_panel(app: AppHandle) {
    panel::toggle(&app)
}

#[tauri::command]
fn begin_drag(app: AppHandle) {
    panel::with_state(&app, |state| state.dragging = true);
}

#[tauri::command]
fn drag_panel(app: AppHandle) {
    let dragging = panel::with_state(&app, |state| state.dragging).unwrap_or(false);
    if dragging {
        panel::drag_to_pointer(&app);
    }
}

#[tauri::command]
fn end_drag(app: AppHandle) {
    if let Some(settings) = panel::with_state(&app, |state| {
        state.dragging = false;
        state.settings.clone()
    }) {
        settings.save();
    }
}

#[tauri::command]
fn update_settings(app: AppHandle, mut settings: Settings) {
    strip_secrets(&app, &mut settings);
    let Some(expanded) = panel::with_state(&app, |state| {
        state.settings = settings.clone();
        state.expanded
    }) else {
        return;
    };
    settings.save();
    panel::refresh(&app, expanded);
}

/// Drops any `secret` setting that arrived among the preferences before they are saved.
///
/// The settings window routes secrets through `set_widget_secret` and never puts one
/// here, so this is a backstop rather than a path: it is what keeps a credential out of
/// `settings.json` if a widget changes a field to `secret` after a value was already
/// stored, or if some future caller forgets.
fn strip_secrets(app: &AppHandle, settings: &mut Settings) {
    let Some(catalog) = panel::with_state(app, |state| state.catalog.clone()) else {
        return;
    };
    for slot in &mut settings.slots {
        let Some(package) = catalog.package(&slot.widget_id) else {
            continue;
        };
        for key in package.manifest.secret_keys() {
            slot.preferences.remove(&key);
        }
    }
}

/// Files a widget's credential in the OS store. An empty value clears it.
#[tauri::command]
fn set_widget_secret(app: AppHandle, widget_id: String, key: String, value: String) -> Result<(), String> {
    secrets::set(&widget_id, &key, &value)?;
    // The widget is reading its settings on load, so it needs to see the new value.
    panel::bump_revision(&app, &widget_id);
    Ok(())
}

/// Which of a widget's secrets are filed — never their values, so the settings window
/// can show "Set" without ever reading a credential back out of the store.
#[tauri::command]
fn widget_secrets_set(app: AppHandle, widget_id: String) -> Vec<String> {
    panel::with_state(&app, |state| state.catalog.clone())
        .and_then(|catalog| catalog.package(&widget_id).cloned())
        .map(|package| {
            package
                .manifest
                .secret_keys()
                .into_iter()
                .filter(|key| secrets::is_set(&widget_id, key))
                .collect()
        })
        .unwrap_or_default()
}

#[tauri::command]
fn log_frontend(message: String) {
    println!("NOTCHLY-FRONTEND {message}");
}

#[tauri::command]
async fn widget_invoke(
    app: AppHandle,
    widget_id: String,
    method: String,
    params: serde_json::Value,
) -> Result<serde_json::Value, String> {
    bridge::dispatch(app, widget_id, method, params).await
}

#[tauri::command]
fn list_widgets(app: AppHandle) -> widgets::Catalog {
    panel::with_state(&app, |state| state.catalog.clone()).unwrap_or_default()
}

#[tauri::command]
fn reload_widget(app: AppHandle, widget_id: String) {
    panel::bump_revision(&app, &widget_id);
}

#[tauri::command]
fn widget_log(app: AppHandle, widget_id: String) -> Vec<String> {
    panel::with_state(&app, |state| {
        state.widget_logs.get(&widget_id).cloned().unwrap_or_default()
    })
    .unwrap_or_default()
}

#[tauri::command]
fn builtin_widgets() -> Vec<builtins::Descriptor> {
    builtins::all()
}

/// The Strip as it would be drawn for `settings`, so the Settings window can model it
/// without a second implementation of the arithmetic.
#[tauri::command]
fn panel_preview(settings: Settings) -> geometry::StripPreview {
    geometry::StripPreview::resolve(&settings)
}

#[tauri::command]
fn list_displays(app: AppHandle) -> Vec<String> {
    app.get_webview_window(panel::PANEL_LABEL)
        .and_then(|window| window.available_monitors().ok())
        .map(|monitors| monitors.iter().filter_map(|m| m.name().cloned()).collect())
        .unwrap_or_default()
}

/// Opens the settings window, or brings it forward if it already exists.
///
/// Must never run on the main thread. On Windows `build()` blocks until the event loop
/// has created the window, so calling it from the loop's own thread deadlocks: the
/// window appears but its WebView2 never finishes navigating, leaving it blank white.
/// Every caller either awaits this from the async runtime or is already off-thread.
fn build_settings_window(app: &AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("settings") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
        return Ok(());
    }
    tauri::WebviewWindowBuilder::new(
        app,
        "settings",
        tauri::WebviewUrl::App("settings.html".into()),
    )
    .title("Notchly Settings")
    .inner_size(720.0, 620.0)
    .min_inner_size(660.0, 520.0)
    .resizable(true)
    .center()
    .focused(true)
    .build()
    .map(|_| ())
    .map_err(|error| error.to_string())
}

/// `async` so Tauri runs it on the async runtime rather than the main thread — see
/// `build_settings_window`.
/// Clicking an icon on the compact strip, rather than resting on it. Same popover, no
/// wait — the click already said which widget was meant.
#[tauri::command]
fn show_widget_popover(app: AppHandle, widget_id: Option<String>) {
    panel::set_popover(&app, widget_id.map(panel::Popover::Widget));
}

#[tauri::command]
async fn open_settings(app: AppHandle) -> Result<(), String> {
    build_settings_window(&app)
}

#[tauri::command]
fn create_starter_widget(app: AppHandle, name: String) -> Result<String, String> {
    let folder = widgets::create_starter(&settings::widgets_dir(), &name)?;
    panel::rescan_widgets(&app);
    Ok(folder.display().to_string())
}

#[tauri::command]
fn reinstall_examples(app: AppHandle) -> usize {
    let count = app
        .path()
        .resource_dir()
        .map(|resources| widgets::copy_examples(&resources, &settings::widgets_dir(), true))
        .unwrap_or(0);
    panel::rescan_widgets(&app);
    count
}

#[tauri::command]
fn reload_all_widgets(app: AppHandle) {
    let ids = panel::with_state(&app, |state| {
        state.catalog.packages.iter().map(|p| p.manifest.id.clone()).collect::<Vec<_>>()
    })
    .unwrap_or_default();
    panel::with_state(&app, |state| {
        for id in ids {
            *state.revisions.entry(id).or_insert(0) += 1;
        }
    });
    panel::rescan_widgets(&app);
}

#[tauri::command]
fn search_apps(app: AppHandle, query: String) -> Vec<services::apps::App> {
    let apps = panel::with_state(&app, |state| state.apps.clone()).unwrap_or_default();
    services::apps::rank(&query, &apps, 8).into_iter().cloned().collect()
}

#[tauri::command]
fn launch_app(path: String) -> Result<(), String> {
    services::apps::launch(std::path::Path::new(&path))
}

#[tauri::command]
fn open_widgets_folder() {
    let path = settings::widgets_dir().display().to_string();
    let _ = tauri_plugin_opener::open_path(path, None::<&str>);
}

/// Menu bar actions. Kept beside the commands rather than in `tray` so every way of
/// changing settings — menu, panel, or settings window — goes through one path.
pub fn handle_tray_action(app: &AppHandle, id: &str) {
    match id {
        "toggle" => panel::toggle(app),
        "quit" => app.exit(0),
        "widgets" => {
            let path = settings::widgets_dir().display().to_string();
            let _ = tauri_plugin_opener::open_path(path, None::<&str>);
        }
        "settings" => {
            // Off the main thread: the tray handler runs on the event loop.
            let app = app.clone();
            tauri::async_runtime::spawn(async move {
                let _ = build_settings_window(&app);
            });
        }
        "login" => {
            let enable = !panel::with_state(app, |state| state.settings.launch_at_login)
                .unwrap_or(false);
            apply_launch_at_login(app, enable);
            mutate_settings(app, move |settings| settings.launch_at_login = enable);
        }
        other => {
            if let Some((_, edge, _)) = tray::EDGES.iter().find(|(id, _, _)| *id == other) {
                let edge = *edge;
                mutate_settings(app, move |settings| settings.edge = edge);
            }
        }
    }
}

/// Applies a change to the stored settings, persists it, and re-lays out the panel.
fn mutate_settings(app: &AppHandle, change: impl FnOnce(&mut Settings)) {
    let Some((settings, expanded)) = panel::with_state(app, |state| {
        change(&mut state.settings);
        (state.settings.clone(), state.expanded)
    }) else {
        return;
    };
    settings.save();
    panel::refresh(app, expanded);
}

/// Registering the login item can fail — a sandboxed or unbundled build, say — so read
/// the real state back rather than assuming the change took.
fn apply_launch_at_login(app: &AppHandle, enable: bool) {
    use tauri_plugin_autostart::ManagerExt;
    let manager = app.autolaunch();
    let result = if enable { manager.enable() } else { manager.disable() };
    if let Err(error) = result {
        eprintln!("NOTCHLY-WARN launch at login: {error}");
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let settings = Settings::load();

    let hotkey = settings.hotkey.clone();

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_notification::init())
        // Widget files are served from here rather than the filesystem directly, so the
        // runtime can be injected and a Content-Security-Policy applied per widget.
        .register_uri_scheme_protocol("widget", |ctx, request| {
            serve_widget(ctx.app_handle(), request)
        })
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, _shortcut, event| {
                    // Fire on press only; the release event would toggle straight back.
                    if event.state() == tauri_plugin_global_shortcut::ShortcutState::Pressed {
                        panel::toggle(app);
                    }
                })
                .build(),
        )
        .manage(Mutex::new(PanelState::new(settings)) as SharedPanel)
        .invoke_handler(tauri::generate_handler![
            get_state,
            open_panel,
            close_panel,
            toggle_panel,
            begin_drag,
            drag_panel,
            end_drag,
            update_settings,
            log_frontend,
            widget_invoke,
            list_widgets,
            reload_widget,
            widget_log,
            open_widgets_folder,
            search_apps,
            launch_app,
            builtin_widgets,
            list_displays,
            panel_preview,
            open_settings,
            show_widget_popover,
            create_starter_widget,
            reinstall_examples,
            reload_all_widgets,
            app_version,
            check_update,
            install_update,
            set_widget_secret,
            widget_secrets_set
        ])
        .setup(move |app| {
            // Notchly is an accessory app: no Dock tile, just the panel.
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            let window = app
                .get_webview_window(PANEL_LABEL)
                .expect("panel window is declared in tauri.conf.json");
            platform::configure_panel(&window);

            let handle = app.handle().clone();
            let _ = APP.set(handle.clone());

            // Bundled starter widgets, so the folder is never an empty void.
            if let Ok(resources) = handle.path().resource_dir() {
                widgets::seed_examples(&resources, &settings::widgets_dir());
            }
            panel::rescan_widgets(&handle);

            // Indexing applications touches the disk; keep it off the launch path.
            let indexer = handle.clone();
            std::thread::spawn(move || {
                let apps = services::apps::scan();
                panel::with_state(&indexer, |state| state.apps = apps);
            });
            start_widget_watcher(&handle);
            let clipboard = crate::services::clipboard::Watcher::spawn(handle.clone());
            std::mem::forget(clipboard);
            let hover = hover::Watchdog::spawn(handle.clone());
            std::mem::forget(hover);

            tray::build(&handle)?;
            register_hotkey(&handle, &hotkey);
            panel::refresh_when_ready(&handle, false);

            // Development harness: walk the panel through its states and save a PNG of
            // each one. The panel only ever appears at the edge of a live display, so
            // this is the only practical way to review how it actually looks. Behind a
            // feature so neither it nor the image codecs it needs ship in a release.
            #[cfg(feature = "capture")]
            if let Ok(dir) = std::env::var("NOTCHLY_CAPTURE_DIR") {
                let capture_handle = handle.clone();
                std::thread::spawn(move || run_capture_pass(capture_handle, dir));
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running Notchly");
}

/// Steps the panel through idle and open, saving a capture of each.
#[cfg(feature = "capture")]
fn run_capture_pass(app: AppHandle, dir: String) {
    let _ = std::fs::create_dir_all(&dir);

    fn shot_window(app: &AppHandle, dir: &str, name: &str, window_label: &str) {
        let path = format!("{dir}/{name}.png");
        let label = name.to_string();
        let target = window_label.to_string();
        let handle = app.clone();
        let _ = app.run_on_main_thread(move || {
            if let Some(window) = handle.get_webview_window(&target) {
                println!(
                    "NOTCHLY-CAPTURE {label} {}",
                    platform::capture_png(&window, &path)
                );
            }
        });
    }

    let shot = |name: &str| shot_window(&app, &dir, name, PANEL_LABEL);

    std::thread::sleep(std::time::Duration::from_millis(2200));
    shot("idle");

    // Transparency is the one capability the whole app rests on, and a regression in
    // it would be invisible to the test suite — so report it alongside the captures.
    {
        let probe = app.clone();
        let _ = app.run_on_main_thread(move || {
            if let Some(window) = probe.get_webview_window(PANEL_LABEL) {
                println!("NOTCHLY-WINDOW {}", platform::describe_window(&window));
                println!("NOTCHLY-PIXELS {}", platform::sample_transparency(&window));
            }
        });
    }

    let opener = app.clone();
    let _ = app.run_on_main_thread(move || panel::open(&opener));
    std::thread::sleep(std::time::Duration::from_millis(1400));
    shot("open");

    // Walk the settings window's tabs too; it is the only other surface with layout.
    // Already on the capture thread, which is what `build_settings_window` needs.
    let _ = build_settings_window(&app);
    std::thread::sleep(std::time::Duration::from_millis(1800));
    for tab in ["general", "appearance", "widgets", "custom"] {
        let selector = app.clone();
        let script = format!(
            "document.querySelector('[data-tab=\"{tab}\"]')?.click()"
        );
        let _ = app.run_on_main_thread(move || {
            if let Some(window) = selector.get_webview_window("settings") {
                let _ = window.eval(&script);
            }
        });
        std::thread::sleep(std::time::Duration::from_millis(700));
        shot_window(&app, &dir, &format!("settings-{tab}"), "settings");
    }

    println!("NOTCHLY-CAPTURE-DONE");
}

/// Registers the global shortcut. Carbon-free: the plugin uses the OS hotkey API, so
/// this needs no Accessibility access on macOS.
fn register_hotkey(app: &AppHandle, hotkey: &settings::Hotkey) {
    use tauri_plugin_global_shortcut::GlobalShortcutExt;
    let manager = app.global_shortcut();
    let _ = manager.unregister_all();
    if !hotkey.is_enabled || hotkey.accelerator.is_empty() {
        return;
    }
    if let Err(error) = manager.register(hotkey.accelerator.as_str()) {
        eprintln!("NOTCHLY-WARN hotkey {}: {error}", hotkey.accelerator);
    }
}

/// Serves `widget://localhost/<widget-id>/<path>`.
fn serve_widget(
    app: &AppHandle,
    request: tauri::http::Request<Vec<u8>>,
) -> tauri::http::Response<Vec<u8>> {
    use tauri::http::{Response, StatusCode};

    let not_found = || {
        Response::builder()
            .status(StatusCode::NOT_FOUND)
            .body(b"not found".to_vec())
            .expect("static response")
    };

    let Some((widget_id, relative)) = widget_protocol::split_request(request.uri().path()) else {
        return not_found();
    };
    let Some(folder) = panel::with_state(app, |state| state.catalog.folder_for(&widget_id)).flatten()
    else {
        return not_found();
    };
    let Some(path) = widget_protocol::safe_join(&folder, &relative) else { return not_found() };
    let Ok(bytes) = std::fs::read(&path) else { return not_found() };

    let settings = panel::with_state(app, |state| state.settings.clone()).unwrap_or_default();
    let declared: Vec<widgets::Permission> = panel::with_state(app, |state| {
        state
            .catalog
            .package(&widget_id)
            .and_then(|package| package.manifest.permissions.clone())
            .unwrap_or_default()
    })
    .unwrap_or_default();
    // Only permissions both declared *and* granted shape the policy.
    let granted: Vec<widgets::Permission> = declared
        .into_iter()
        .filter(|permission| {
            !permission.requires_explicit_grant()
                || match permission {
                    widgets::Permission::Network => &settings.network_approved_widgets,
                    widgets::Permission::Shell => &settings.shell_approved_widgets,
                    widgets::Permission::Clipboard => &settings.clipboard_approved_widgets,
                    _ => &settings.network_approved_widgets,
                }
                .contains(&widget_id)
        })
        .collect();

    let content_type = widget_protocol::content_type(&path);
    let body = if content_type.starts_with("text/html") {
        let html = String::from_utf8_lossy(&bytes).to_string();
        let widget_settings = serde_json::to_string(&bridge::widget_settings(app, &widget_id))
            .unwrap_or_else(|_| "{}".into());
        let theme = serde_json::to_string(&bridge::theme_payload(&settings))
            .unwrap_or_else(|_| "{}".into());
        widget_protocol::inject(&html, &widget_id, &widget_settings, &theme).into_bytes()
    } else {
        bytes
    };

    Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", content_type)
        .header("Content-Security-Policy", widget_protocol::csp(&granted))
        .header("Cache-Control", "no-store")
        .body(body)
        .unwrap_or_else(|_| not_found())
}

/// Watches the widgets folder so saving a file reloads the widget in place.
fn start_widget_watcher(app: &AppHandle) {
    use notify::{RecursiveMode, Watcher};

    let handle = app.clone();
    std::thread::spawn(move || {
        let (tx, rx) = std::sync::mpsc::channel();
        let Ok(mut watcher) = notify::recommended_watcher(tx) else { return };
        if watcher
            .watch(&settings::widgets_dir(), RecursiveMode::Recursive)
            .is_err()
        {
            return;
        }
        loop {
            // Editors save in bursts — write, rename, chmod — so coalesce them.
            match rx.recv() {
                Ok(Ok(_)) => {}
                Ok(Err(_)) => continue,
                Err(_) => return,
            }
            while rx.recv_timeout(std::time::Duration::from_millis(220)).is_ok() {}
            let inner = handle.clone();
            let _ = handle.run_on_main_thread(move || {
                let ids = panel::with_state(&inner, |state| {
                    state
                        .catalog
                        .packages
                        .iter()
                        .map(|package| package.manifest.id.clone())
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default();
                panel::with_state(&inner, |state| {
                    for id in ids {
                        *state.revisions.entry(id).or_insert(0) += 1;
                    }
                });
                panel::rescan_widgets(&inner);
            });
        }
    });
}

mod geometry;
mod panel;
mod platform;
mod services;
mod tray;
mod settings;

use panel::{PanelSnapshot, PanelState, SharedPanel, PANEL_LABEL};
use settings::Settings;
use std::sync::Mutex;
use tauri::{AppHandle, Manager};

#[tauri::command]
fn get_state(app: AppHandle) -> Option<PanelSnapshot> {
    panel::with_state(&app, |state| state.last_snapshot.clone())?
}

#[tauri::command]
fn open_panel(app: AppHandle) {
    panel::open(&app)
}

#[tauri::command]
fn close_panel(app: AppHandle) {
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
fn update_settings(app: AppHandle, settings: Settings) {
    let Some(expanded) = panel::with_state(&app, |state| {
        state.settings = settings.clone();
        state.expanded
    }) else {
        return;
    };
    settings.save();
    panel::refresh(&app, expanded);
}

#[tauri::command]
fn log_frontend(message: String) {
    println!("NOTCHLY-FRONTEND {message}");
}

#[tauri::command]
fn capture_panel(app: AppHandle, path: String) -> serde_json::Value {
    match app.get_webview_window(PANEL_LABEL) {
        Some(window) => platform::capture_png(&window, &path),
        None => serde_json::json!({ "error": "panel window missing" }),
    }
}

/// Reports what the native window layer actually looks like. Kept from the Phase 0
/// spike because transparency is the one capability the whole app depends on, and a
/// regression in it would otherwise be invisible to the test suite.
#[tauri::command]
fn window_report(app: AppHandle) -> serde_json::Value {
    match app.get_webview_window(PANEL_LABEL) {
        Some(window) => {
            let mut report = platform::describe_window(&window);
            if let Some(object) = report.as_object_mut() {
                object.insert("pixels".into(), platform::sample_transparency(&window));
            }
            report
        }
        None => serde_json::json!({ "error": "panel window missing" }),
    }
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
        "pin" => mutate_settings(app, |settings| settings.is_pinned = !settings.is_pinned),
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
            window_report,
            capture_panel,
            log_frontend
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
            tray::build(&handle)?;
            register_hotkey(&handle, &hotkey);
            panel::refresh_when_ready(&handle, false);

            // Development harness: walk the panel through its states and save a PNG of
            // each one. The panel only ever appears at the edge of a live display, so
            // this is the only practical way to review how it actually looks.
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
fn run_capture_pass(app: AppHandle, dir: String) {
    let _ = std::fs::create_dir_all(&dir);

    fn shot(app: &AppHandle, dir: &str, name: &str) {
        let path = format!("{dir}/{name}.png");
        let label = name.to_string();
        let handle = app.clone();
        let _ = app.run_on_main_thread(move || {
            if let Some(window) = handle.get_webview_window(PANEL_LABEL) {
                println!(
                    "NOTCHLY-CAPTURE {label} {}",
                    platform::capture_png(&window, &path)
                );
            }
        });
    }

    std::thread::sleep(std::time::Duration::from_millis(2200));
    shot(&app, &dir, "idle");

    let opener = app.clone();
    let _ = app.run_on_main_thread(move || panel::open(&opener));
    std::thread::sleep(std::time::Duration::from_millis(1400));
    shot(&app, &dir, "open");

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

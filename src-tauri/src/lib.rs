mod platform;

use tauri::Manager;


/// Phase 0 spike: bring up a transparent, shaped, always-on-top panel and report back
/// what the window layer actually looks like once it is running.
///
/// The report matters because Tauri's transparency on macOS is known to behave
/// differently in a bundled release build than under `tauri dev`, and Notchly is
/// nothing without a transparent window.
#[tauri::command]
fn window_report(app: tauri::AppHandle) -> serde_json::Value {
    let window = app.get_webview_window("panel");
    match window {
        Some(window) => platform::describe_window(&window),
        None => serde_json::json!({ "error": "panel window missing" }),
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![window_report])
        .setup(|app| {
            let window = app
                .get_webview_window("panel")
                .expect("panel window is declared in tauri.conf.json");
            platform::configure_panel(&window);

            // Print the same report to stdout so a release build can be validated
            // without a human looking at the screen.
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                std::thread::sleep(std::time::Duration::from_millis(1500));
                let inner = handle.clone();
                let _ = handle.run_on_main_thread(move || {
                    if let Some(window) = inner.get_webview_window("panel") {
                        println!(
                            "NOTCHLY-WINDOW-REPORT {}",
                            platform::describe_window(&window)
                        );
                        println!(
                            "NOTCHLY-PIXEL-REPORT {}",
                            platform::sample_transparency(&window)
                        );
                    }
                });
            });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running Notchly");
}

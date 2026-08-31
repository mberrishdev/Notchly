//! Hover-to-open.
//!
//! The pointer is watched here rather than in the web view. A non-activating panel in
//! an accessory app does not reliably deliver `mouseenter`/`mouseleave` to its web
//! content, and the window resizes underneath the pointer as it opens — both of which
//! made the DOM an unreliable place to decide this. Rust owns the window frame, so it
//! can answer "is the pointer over the panel" directly.

use crate::panel;
use crate::settings::ActivationMode;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tauri::{AppHandle, Manager};

const POLL: std::time::Duration = std::time::Duration::from_millis(90);

pub struct Watchdog {
    stop: Arc<AtomicBool>,
}

impl Watchdog {
    pub fn spawn(app: AppHandle) -> Self {
        let stop = Arc::new(AtomicBool::new(false));
        let flag = stop.clone();
        std::thread::spawn(move || {
            let mut inside_since: Option<std::time::Instant> = None;
            let mut outside_since: Option<std::time::Instant> = None;

            while !flag.load(Ordering::Relaxed) {
                std::thread::sleep(POLL);

                let Some(window) = app.get_webview_window(panel::PANEL_LABEL) else { continue };
                let Ok(pointer) = app.cursor_position() else { continue };
                let (Ok(origin), Ok(size)) = (window.outer_position(), window.outer_size()) else {
                    continue;
                };

                let inside = pointer.x >= origin.x as f64
                    && pointer.x < origin.x as f64 + size.width as f64
                    && pointer.y >= origin.y as f64
                    && pointer.y < origin.y as f64 + size.height as f64;

                let Some((expanded, settings)) =
                    panel::with_state(&app, |state| (state.expanded, state.settings.clone()))
                else {
                    continue;
                };

                if inside {
                    outside_since = None;
                    let since = *inside_since.get_or_insert_with(std::time::Instant::now);
                    if !expanded
                        && settings.activation == ActivationMode::Hover
                        && since.elapsed().as_secs_f64() >= settings.open_delay
                        && !panel::hover_suppressed(&app)
                    {
                        let handle = app.clone();
                        let _ = app.run_on_main_thread(move || panel::open(&handle));
                    }
                } else {
                    inside_since = None;
                    let since = *outside_since.get_or_insert_with(std::time::Instant::now);
                    if expanded
                        && !settings.is_pinned
                        && !panel::holds_panel_open(&app)
                        && since.elapsed().as_secs_f64() >= settings.close_delay
                    {
                        let handle = app.clone();
                        let _ = app.run_on_main_thread(move || panel::close(&handle));
                    }
                }
            }
        });
        Self { stop }
    }
}

impl Drop for Watchdog {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

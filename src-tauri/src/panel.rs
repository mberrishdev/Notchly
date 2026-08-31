//! Owns the panel window and the open/close state machine.
//!
//! The window is kept snug around the idle handle and only grows to the full footprint
//! while the panel is open, so Notchly never swallows clicks meant for the desktop.
//! That rule is why the frame is set here, before any animation runs, rather than being
//! animated: the window grows invisibly (it is transparent) and the frontend then
//! animates the shape inside it.

use crate::geometry::{PanelGeometry, Placement, Rect};
use crate::settings::Settings;
use serde::Serialize;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, Emitter, Manager, Monitor, PhysicalPosition, PhysicalSize, WebviewWindow};

pub const PANEL_LABEL: &str = "panel";
/// How long the closing animation runs before the window is allowed to shrink.
const COLLAPSE_ANIMATION_MS: u64 = 340;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PanelSnapshot {
    pub expanded: bool,
    pub metrics: crate::geometry::PanelMetrics,
    pub settings: Settings,
}

pub struct PanelState {
    pub settings: Settings,
    pub expanded: bool,
    /// Bumped on every state change so a stale collapse timer can tell it was replaced.
    generation: Arc<AtomicU64>,
    pub dragging: bool,
    /// The last snapshot emitted, so `get_state` never has to re-enumerate monitors —
    /// which can fail while the app is still starting up.
    pub last_snapshot: Option<PanelSnapshot>,
}

impl PanelState {
    pub fn new(settings: Settings) -> Self {
        Self {
            settings,
            expanded: false,
            generation: Arc::new(AtomicU64::new(0)),
            dragging: false,
            last_snapshot: None,
        }
    }
}

pub type SharedPanel = Mutex<PanelState>;

/// Runs `body` against the shared state.
///
/// Binding the guard with `.ok()` matters: `if let Ok(guard) = ...` keeps the whole
/// `Result` — poisoned guard included — alive in a temporary that outlives the borrow
/// of the managed state, which does not compile.
pub fn with_state<R>(app: &AppHandle, body: impl FnOnce(&mut PanelState) -> R) -> Option<R> {
    let state = app.state::<SharedPanel>();
    let mut guard = state.lock().ok()?;
    Some(body(&mut guard))
}

/// A monitor as the geometry code wants it: logical points, origin at zero, plus what
/// is needed to map back into the physical space Tauri positions windows in.
struct Display {
    logical: Rect,
    origin: PhysicalPosition<i32>,
    scale: f64,
}

/// Picks the display the panel should live on.
///
/// `available_monitors` can come back empty while the app is still starting up, so this
/// asks the window rather than the app handle and falls through several sources rather
/// than giving up on the first empty answer.
fn display_for(app: &AppHandle, settings: &Settings) -> Option<Display> {
    let window = app.get_webview_window(PANEL_LABEL)?;
    let monitors = window.available_monitors().unwrap_or_default();

    let chosen = settings
        .preferred_screen
        .as_ref()
        .and_then(|name| {
            monitors
                .iter()
                .find(|m| m.name().map(|n| n == name).unwrap_or(false))
                .cloned()
        })
        .or_else(|| {
            let pointer = app.cursor_position().ok()?;
            monitors
                .iter()
                .find(|m| contains_physical(m, pointer.x, pointer.y))
                .cloned()
        })
        .or_else(|| window.current_monitor().ok().flatten())
        .or_else(|| window.primary_monitor().ok().flatten())
        .or_else(|| monitors.first().cloned())?;

    Some(to_display(&chosen))
}

fn to_display(monitor: &Monitor) -> Display {
    let scale = monitor.scale_factor();
    let size: &PhysicalSize<u32> = monitor.size();
    Display {
        logical: Rect::new(0.0, 0.0, size.width as f64 / scale, size.height as f64 / scale),
        origin: *monitor.position(),
        scale,
    }
}

fn contains_physical(monitor: &Monitor, x: f64, y: f64) -> bool {
    let position = monitor.position();
    let size = monitor.size();
    x >= position.x as f64
        && x < position.x as f64 + size.width as f64
        && y >= position.y as f64
        && y < position.y as f64 + size.height as f64
}

/// Applies a frame expressed in the display's logical points.
fn apply_frame(window: &WebviewWindow, display: &Display, frame: Rect) {
    let scale = display.scale;
    let position = PhysicalPosition::new(
        (display.origin.x as f64 + frame.x * scale).round() as i32,
        (display.origin.y as f64 + frame.y * scale).round() as i32,
    );
    let size = PhysicalSize::new(
        (frame.width * scale).round().max(1.0) as u32,
        (frame.height * scale).round().max(1.0) as u32,
    );
    // Size before position, so the window never straddles two monitors mid-move.
    let _ = window.set_size(size);
    let _ = window.set_position(position);
}

/// Retries `refresh` until a display is available. Called once at startup, where the
/// window server may not have reported any monitors yet.
pub fn refresh_when_ready(app: &AppHandle, expanded: bool) {
    let handle = app.clone();
    std::thread::spawn(move || {
        for attempt in 0..40 {
            let inner = handle.clone();
            let (tx, rx) = std::sync::mpsc::channel();
            let _ = handle.run_on_main_thread(move || {
                refresh(&inner, expanded);
                let ready = with_state(&inner, |state| state.last_snapshot.is_some())
                    .unwrap_or(false);
                let _ = tx.send(ready);
            });
            if rx.recv_timeout(std::time::Duration::from_secs(2)).unwrap_or(false) {
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(50 * (attempt / 8 + 1)));
        }
        eprintln!("NOTCHLY-WARN gave up waiting for a display");
    });
}

pub fn refresh(app: &AppHandle, expanded: bool) {
    let Some(window) = app.get_webview_window(PANEL_LABEL) else { return };
    let settings = {
        let state = app.state::<SharedPanel>();
        let guard = state.lock().unwrap();
        guard.settings.clone()
    };
    let Some(display) = display_for(app, &settings) else {
        eprintln!("NOTCHLY-WARN refresh: no display available yet");
        return;
    };

    let geometry = PanelGeometry::new(&settings, display.logical, settings.enabled_slot_count());
    apply_frame(&window, &display, geometry.window_frame(expanded));

    let snapshot = PanelSnapshot {
        expanded,
        metrics: geometry.metrics(expanded),
        settings,
    };
    with_state(app, |state| state.last_snapshot = Some(snapshot.clone()));
    let _ = app.emit("panel-state", snapshot);
}

pub fn open(app: &AppHandle) {
    {
        let state = app.state::<SharedPanel>();
        let mut guard = state.lock().unwrap();
        if guard.expanded {
            return;
        }
        guard.expanded = true;
        guard.generation.fetch_add(1, Ordering::SeqCst);
    }
    // Grow the (transparent) window first so the animation has room to play out.
    refresh(app, true);
    if let Some(window) = app.get_webview_window(PANEL_LABEL) {
        let _ = window.show();
    }
}

pub fn close(app: &AppHandle) {
    let generation = {
        let state = app.state::<SharedPanel>();
        let mut guard = state.lock().unwrap();
        if !guard.expanded || guard.settings.is_pinned {
            return;
        }
        guard.expanded = false;
        guard.generation.fetch_add(1, Ordering::SeqCst) + 1
    };

    // Tell the frontend to animate closed, then shrink the window once it has.
    let Some(window) = app.get_webview_window(PANEL_LABEL) else { return };
    let settings = {
        let state = app.state::<SharedPanel>();
        let guard = state.lock().unwrap();
        guard.settings.clone()
    };
    if let Some(display) = display_for(app, &settings) {
        let geometry = PanelGeometry::new(&settings, display.logical, settings.enabled_slot_count());
        let _ = app.emit(
            "panel-state",
            PanelSnapshot {
                expanded: false,
                metrics: geometry.metrics(false),
                settings,
            },
        );
    }
    let _ = window;

    let handle = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_millis(COLLAPSE_ANIMATION_MS));
        let generation_now = {
            let state = handle.state::<SharedPanel>();
            let guard = state.lock().unwrap();
            if guard.expanded {
                return;
            }
            guard.generation.load(Ordering::SeqCst)
        };
        if generation_now != generation {
            return;
        }
        let inner = handle.clone();
        let _ = handle.run_on_main_thread(move || refresh(&inner, false));
    });
}

pub fn toggle(app: &AppHandle) {
    let expanded = {
        let state = app.state::<SharedPanel>();
        let guard = state.lock().unwrap();
        guard.expanded
    };
    if expanded {
        // An explicit toggle closes even when pinned.
        {
            let state = app.state::<SharedPanel>();
            let mut guard = state.lock().unwrap();
            guard.settings.is_pinned = false;
        }
        close(app);
    } else {
        open(app);
    }
}

/// Repositioning by dragging the panel itself. The pointer's absolute position drives
/// the panel rather than an accumulated translation, so it cannot drift away from the
/// cursor as the window moves underneath it.
pub fn drag_to_pointer(app: &AppHandle) {
    let Ok(pointer) = app.cursor_position() else { return };
    let Ok(monitors) = app.available_monitors() else { return };
    let Some(monitor) = monitors
        .iter()
        .find(|m| contains_physical(m, pointer.x, pointer.y))
        .or_else(|| monitors.first())
    else {
        return;
    };
    let display = to_display(monitor);
    let local_x = (pointer.x - display.origin.x as f64) / display.scale;
    let local_y = (pointer.y - display.origin.y as f64) / display.scale;

    let Some(placement) = Placement::resolve(local_x, local_y, display.logical) else { return };

    let expanded = {
        let state = app.state::<SharedPanel>();
        let mut guard = state.lock().unwrap();
        guard.settings.edge = placement.edge;
        guard.settings.alignment = placement.alignment;
        // Only re-pin the display if the user had pinned one.
        if guard.settings.preferred_screen.is_some() {
            guard.settings.preferred_screen = monitor.name().cloned();
        }
        guard.expanded
    };
    refresh(app, expanded);
}

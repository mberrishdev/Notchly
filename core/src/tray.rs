//! The menu bar item.
//!
//! Notchly runs as an accessory app with no Dock tile, so this is its only chrome: a
//! way to reach the panel, its edge, and its settings without the keyboard.

use crate::panel;
use crate::settings::ScreenEdge;
use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::AppHandle;

pub const EDGES: [(&str, ScreenEdge, &str); 4] = [
    ("edge-top", ScreenEdge::Top, "Dock Top"),
    ("edge-bottom", ScreenEdge::Bottom, "Dock Bottom"),
    ("edge-leading", ScreenEdge::Leading, "Dock Left"),
    ("edge-trailing", ScreenEdge::Trailing, "Dock Right"),
];

pub fn build(app: &AppHandle) -> tauri::Result<()> {
    let settings = panel::with_state(app, |state| state.settings.clone()).unwrap_or_default();

    let toggle = MenuItem::with_id(app, "toggle", "Show Panel", true, None::<&str>)?;
    let pin = CheckMenuItem::with_id(
        app, "pin", "Keep Panel Open", true, settings.is_pinned, None::<&str>,
    )?;
    let login = CheckMenuItem::with_id(
        app, "login", "Launch at Login", true, settings.launch_at_login, None::<&str>,
    )?;
    let edges: Vec<CheckMenuItem<_>> = EDGES
        .iter()
        .map(|(id, edge, label)| {
            CheckMenuItem::with_id(app, id, label, true, settings.edge == *edge, None::<&str>)
        })
        .collect::<tauri::Result<_>>()?;

    let settings_item = MenuItem::with_id(app, "settings", "Settings…", true, Some("CmdOrCtrl+,"))?;
    let widgets = MenuItem::with_id(app, "widgets", "Open Widgets Folder", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit Notchly", true, Some("CmdOrCtrl+Q"))?;

    let menu = Menu::with_items(
        app,
        &[
            &toggle,
            &pin,
            &login,
            &PredefinedMenuItem::separator(app)?,
            &edges[0],
            &edges[1],
            &edges[2],
            &edges[3],
            &PredefinedMenuItem::separator(app)?,
            &widgets,
            &settings_item,
            &PredefinedMenuItem::separator(app)?,
            &quit,
        ],
    )?;

    // The app icon can't double as the tray icon: a template image keeps only the
    // alpha channel, so the whole squircle plate renders as a solid blob. This is a
    // mark drawn for 18pt, which is the height Tauri scales tray icons to.
    TrayIconBuilder::with_id("notchly")
        .icon(tauri::include_image!("icons/menubar.png"))
        .icon_as_template(true)
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| {
            crate::handle_tray_action(app, event.id().as_ref());
        })
        .build(app)?;
    Ok(())
}

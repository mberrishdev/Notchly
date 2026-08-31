//! Notification Center banners, for widgets that asked for them.

use tauri_plugin_notification::NotificationExt;

pub fn post(title: &str, body: &str) {
    if let Some(app) = crate::app_handle() {
        let _ = app.notification().builder().title(title).body(body).show();
    }
}

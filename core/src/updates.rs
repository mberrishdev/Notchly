//! Checking for and installing updates.
//!
//! Tauri's updater is used rather than Sparkle, which only exists for macOS: one
//! implementation covers both platforms, and the bundler already knows how to produce
//! the signed manifest it reads.
//!
//! Every release is signed with a key that never leaves the maintainer's machine and
//! verified here before anything is installed, so a compromised release host cannot
//! push an update on its own.

use serde::Serialize;
use tauri::AppHandle;
use tauri_plugin_updater::UpdaterExt;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase", tag = "status")]
pub enum UpdateStatus {
    /// Already on the newest release.
    UpToDate { version: String },
    Available {
        version: String,
        current: String,
        notes: Option<String>,
    },
    /// Checking failed — offline, rate limited, or no manifest published yet. The
    /// reason is shown rather than swallowed, so "no updates" never silently means
    /// "the check is broken".
    Failed { reason: String },
}

pub fn current_version(app: &AppHandle) -> String {
    app.package_info().version.to_string()
}

pub async fn check(app: AppHandle) -> UpdateStatus {
    let current = current_version(&app);
    let updater = match app.updater() {
        Ok(updater) => updater,
        Err(error) => {
            return UpdateStatus::Failed {
                reason: error.to_string(),
            }
        }
    };
    match updater.check().await {
        Ok(Some(update)) => UpdateStatus::Available {
            version: update.version.clone(),
            current,
            notes: update.body.clone(),
        },
        Ok(None) => UpdateStatus::UpToDate { version: current },
        Err(error) => UpdateStatus::Failed {
            reason: error.to_string(),
        },
    }
}

/// Downloads and installs, then restarts into the new version.
///
/// The download is verified against the public key baked into the app before a single
/// byte is executed; a failed signature is an error, not a warning.
pub async fn install(app: AppHandle) -> Result<(), String> {
    let updater = app.updater().map_err(|error| error.to_string())?;
    let Some(update) = updater.check().await.map_err(|error| error.to_string())? else {
        return Err("Notchly is already up to date.".into());
    };

    update
        .download_and_install(|_chunk, _total| {}, || {})
        .await
        .map_err(|error| error.to_string())?;

    // On Windows the installer takes over and exits the app itself; on macOS the
    // bundle is swapped in place and the process has to be restarted.
    app.restart();
}

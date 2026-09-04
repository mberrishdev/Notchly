//! Decides when the system needs sampling at all.
//!
//! The rule from the Swift version carries over unchanged: the fastest requested
//! cadence wins, and no requester at all stops sampling entirely. That is the default
//! state, because the default idle handle shows only the clock and the clock samples
//! nothing.

use super::metrics::{Cadence, MetricsSample, SamplerHandle};
use crate::panel::Popover;
use crate::settings::Settings;
use tauri::{AppHandle, Emitter};

#[derive(Default)]
pub struct Ambient {
    sampler: Option<SamplerHandle>,
    running: Option<(Cadence, bool)>,
    media: Option<MediaPoller>,
    media_cadence: Option<Cadence>,
}

/// Now Playing is polled rather than pushed on macOS: reading it costs an `osascript`
/// subprocess, so the ambient rate is deliberately lazy.
pub struct MediaPoller {
    stop: std::sync::Arc<std::sync::atomic::AtomicBool>,
}

impl MediaPoller {
    fn spawn(app: AppHandle, cadence: Cadence) -> Self {
        use std::sync::atomic::{AtomicBool, Ordering};
        let stop = std::sync::Arc::new(AtomicBool::new(false));
        let flag = stop.clone();
        let interval = match cadence {
            Cadence::Live => std::time::Duration::from_millis(1500),
            Cadence::Ambient => std::time::Duration::from_secs(6),
        };
        std::thread::spawn(move || {
            while !flag.load(Ordering::Relaxed) {
                let payload = crate::services::media::now_playing();
                let _ = app.emit("media", &payload);
                std::thread::sleep(interval);
            }
        });
        Self { stop }
    }
}

impl Drop for MediaPoller {
    fn drop(&mut self) {
        self.stop.store(true, std::sync::atomic::Ordering::Relaxed);
    }
}

impl Ambient {
    /// Starts, stops, or re-paces sampling to match what is currently on screen.
    ///
    /// The compact strip is why `popover` is here: opening it puts nothing but glyphs on
    /// screen, so it must not request Live sampling the way the Widget Stack does. Only
    /// the card the pointer actually opened counts as a reading being displayed.
    pub fn sync(
        &mut self,
        app: &AppHandle,
        expanded: bool,
        settings: &Settings,
        popover: Option<&Popover>,
    ) {
        let showing = |widget_id: &str| popover.and_then(Popover::widget_id) == Some(widget_id);
        let row_for = |widget_id: &str| {
            expanded
                && settings
                    .slots
                    .iter()
                    .any(|slot| slot.is_enabled && slot.widget_id == widget_id)
        };

        let wanted = if showing("system") {
            // Only the Popover shows the process list; the Row is one percentage.
            Some((Cadence::Live, true))
        } else if row_for("system") || settings.handle_chips.iter().any(|chip| chip.needs_metrics())
        {
            Some((Cadence::Ambient, false))
        } else {
            None
        };

        // Now Playing is wanted by its Popover, its Row, and the idle indicator chip.
        let media_wanted = if showing("media") {
            Some(Cadence::Live)
        } else if row_for("media") || settings.handle_chips.iter().any(|chip| chip.needs_media()) {
            Some(Cadence::Ambient)
        } else {
            None
        };
        if media_wanted != self.media_cadence {
            self.media_cadence = media_wanted;
            self.media = media_wanted.map(|cadence| MediaPoller::spawn(app.clone(), cadence));
        }

        if wanted == self.running {
            return;
        }
        self.running = wanted;
        self.sampler = None;

        let Some((cadence, want_processes)) = wanted else { return };
        let handle = app.clone();
        self.sampler = Some(SamplerHandle::spawn(cadence, want_processes, move |sample| {
            crate::panel::with_state(&handle, |state| state.last_metrics = Some(sample.clone()));
            let _ = handle.emit("metrics", &sample);
        }));
    }

    /// One-shot sample, so a freshly opened panel isn't blank until the first tick.
    pub fn sample_now(app: &AppHandle, want_processes: bool) {
        let handle = app.clone();
        std::thread::spawn(move || {
            let mut sampler = super::metrics::Sampler::new();
            let _ = sampler.sample(false);
            std::thread::sleep(std::time::Duration::from_millis(250));
            let sample: MetricsSample = sampler.sample(want_processes);
            crate::panel::with_state(&handle, |state| state.last_metrics = Some(sample.clone()));
            let _ = handle.emit("metrics", &sample);
        });
    }
}

//! Decides when the system needs sampling at all.
//!
//! The rule from the Swift version carries over unchanged: the fastest requested
//! cadence wins, and no requester at all stops sampling entirely. That is the default
//! state, because the default idle handle shows only the clock and the clock samples
//! nothing.

use super::metrics::{Cadence, MetricsSample, SamplerHandle};
use crate::settings::Settings;
use tauri::{AppHandle, Emitter};

#[derive(Default)]
pub struct Ambient {
    sampler: Option<SamplerHandle>,
    running: Option<(Cadence, bool)>,
}

impl Ambient {
    /// Starts, stops, or re-paces sampling to match what is currently on screen.
    pub fn sync(&mut self, app: &AppHandle, expanded: bool, settings: &Settings) {
        let wanted = if expanded {
            // The open panel shows the System widget, which wants the process list.
            Some((Cadence::Live, true))
        } else if settings.handle_chips.iter().any(|chip| chip.needs_metrics()) {
            Some((Cadence::Ambient, false))
        } else {
            None
        };

        if wanted == self.running {
            return;
        }
        self.running = wanted;
        self.sampler = None;

        let Some((cadence, want_processes)) = wanted else { return };
        let handle = app.clone();
        self.sampler = Some(SamplerHandle::spawn(cadence, want_processes, move |sample| {
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
            let _ = handle.emit("metrics", &sample);
        });
    }
}

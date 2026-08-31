//! System readings for the System widget and the idle handle chips.
//!
//! Sampling is refcounted against what is actually on screen, at one of two cadences:
//! `Live` while the panel is open, `Ambient` while it is closed but an idle chip needs
//! a value. With the default handle — the clock alone — nothing samples at all.

use serde::Serialize;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use sysinfo::{Disks, Networks, System};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Cadence {
    Live,
    Ambient,
}

impl Cadence {
    fn interval(self) -> std::time::Duration {
        std::time::Duration::from_millis(match self {
            Cadence::Live => 1000,
            Cadence::Ambient => 5000,
        })
    }
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BatterySample {
    pub present: bool,
    pub level: f64,
    pub charging: bool,
    pub plugged_in: bool,
    pub minutes_remaining: Option<i64>,
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProcessSample {
    pub name: String,
    pub cpu: f64,
    pub memory: u64,
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MetricsSample {
    /// 0…1 across all cores.
    pub cpu: f64,
    pub memory: f64,
    pub memory_used: u64,
    pub memory_total: u64,
    pub disk_free: u64,
    pub disk_total: u64,
    pub disk: f64,
    pub network_down: f64,
    pub network_up: f64,
    pub uptime: u64,
    pub battery: BatterySample,
    pub top_processes: Vec<ProcessSample>,
}

pub struct Sampler {
    system: System,
    networks: Networks,
    disks: Disks,
    previous_network: Option<(u64, u64, std::time::Instant)>,
    battery_manager: Option<starship_battery::Manager>,
}

impl Sampler {
    pub fn new() -> Self {
        Self {
            system: System::new(),
            networks: Networks::new_with_refreshed_list(),
            disks: Disks::new_with_refreshed_list(),
            previous_network: None,
            battery_manager: starship_battery::Manager::new().ok(),
        }
    }

    pub fn sample(&mut self, want_processes: bool) -> MetricsSample {
        self.system.refresh_cpu_usage();
        self.system.refresh_memory();
        if want_processes {
            self.system.refresh_processes(sysinfo::ProcessesToUpdate::All, true);
        }
        self.networks.refresh(true);
        self.disks.refresh(true);

        let memory_total = self.system.total_memory();
        let memory_used = self.system.used_memory();

        // The volume the user actually lives on, rather than every mount point.
        let (disk_free, disk_total) = self
            .disks
            .iter()
            .find(|disk| disk.mount_point() == std::path::Path::new("/"))
            .or_else(|| self.disks.iter().next())
            .map(|disk| (disk.available_space(), disk.total_space()))
            .unwrap_or((0, 1));

        let (received, transmitted) = self
            .networks
            .iter()
            .fold((0u64, 0u64), |(rx, tx), (_, data)| {
                (rx + data.total_received(), tx + data.total_transmitted())
            });
        let now = std::time::Instant::now();
        let (down, up) = match self.previous_network {
            Some((prev_rx, prev_tx, at)) => {
                let elapsed = now.duration_since(at).as_secs_f64().max(0.2);
                (
                    received.saturating_sub(prev_rx) as f64 / elapsed,
                    transmitted.saturating_sub(prev_tx) as f64 / elapsed,
                )
            }
            None => (0.0, 0.0),
        };
        self.previous_network = Some((received, transmitted, now));

        let mut top_processes = Vec::new();
        if want_processes {
            let mut all: Vec<_> = self
                .system
                .processes()
                .values()
                .map(|process| ProcessSample {
                    name: process.name().to_string_lossy().to_string(),
                    cpu: process.cpu_usage() as f64 / 100.0,
                    memory: process.memory(),
                })
                .collect();
            all.sort_by(|a, b| b.cpu.partial_cmp(&a.cpu).unwrap_or(std::cmp::Ordering::Equal));
            all.truncate(5);
            top_processes = all;
        }

        MetricsSample {
            cpu: (self.system.global_cpu_usage() as f64 / 100.0).clamp(0.0, 1.0),
            memory: if memory_total == 0 { 0.0 } else { memory_used as f64 / memory_total as f64 },
            memory_used,
            memory_total,
            disk_free,
            disk_total,
            disk: if disk_total == 0 {
                0.0
            } else {
                (disk_total - disk_free) as f64 / disk_total as f64
            },
            network_down: down.max(0.0),
            network_up: up.max(0.0),
            uptime: System::uptime(),
            battery: self.battery(),
            top_processes,
        }
    }

    fn battery(&mut self) -> BatterySample {
        let Some(manager) = self.battery_manager.as_ref() else {
            return BatterySample::default();
        };
        let Ok(mut batteries) = manager.batteries() else {
            return BatterySample::default();
        };
        let Some(Ok(battery)) = batteries.next() else {
            return BatterySample::default();
        };

        use starship_battery::State;
        let charging = matches!(battery.state(), State::Charging);
        let remaining = if charging {
            battery.time_to_full()
        } else {
            battery.time_to_empty()
        };
        BatterySample {
            present: true,
            level: f64::from(battery.state_of_charge().value).clamp(0.0, 1.0),
            charging,
            plugged_in: !matches!(battery.state(), State::Discharging),
            minutes_remaining: remaining.map(|time| (f64::from(time.value) / 60.0) as i64),
        }
    }
}

/// Runs the sampling loop on its own thread until told to stop.
pub struct SamplerHandle {
    stop: Arc<AtomicBool>,
}

impl SamplerHandle {
    pub fn spawn<F>(cadence: Cadence, want_processes: bool, mut emit: F) -> Self
    where
        F: FnMut(MetricsSample) + Send + 'static,
    {
        let stop = Arc::new(AtomicBool::new(false));
        let flag = stop.clone();
        std::thread::spawn(move || {
            let mut sampler = Sampler::new();
            // The first CPU reading is meaningless without a baseline to diff against.
            let _ = sampler.sample(false);
            std::thread::sleep(std::time::Duration::from_millis(300));
            while !flag.load(Ordering::Relaxed) {
                emit(sampler.sample(want_processes));
                std::thread::sleep(cadence.interval());
            }
        });
        Self { stop }
    }
}

impl Drop for SamplerHandle {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

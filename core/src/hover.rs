//! Hover-to-open.
//!
//! The pointer is watched here rather than in the web view. A non-activating panel in
//! an accessory app does not reliably deliver `mouseenter`/`mouseleave` to its web
//! content, and the window resizes underneath the pointer as it opens — both of which
//! made the DOM an unreliable place to decide this. Rust owns the window frame, so it
//! can answer "is the pointer over the panel" directly.

use crate::geometry::{
    chip_at, chip_spans, popover_offset, row_at, row_spans, StripRow, HOVER_BUFFER,
};
use crate::panel::{self, Popover};
use crate::settings::{ActivationMode, ScreenEdge};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tauri::{AppHandle, Manager};

const POLL: std::time::Duration = std::time::Duration::from_millis(90);

/// Shorter than any open delay: a popover is a glance, and waiting for it to appear
/// would make resting on a reading feel like nothing had happened.
const POPOVER_DELAY: f64 = 0.12;

/// Where the pointer is, relative to whatever narrow shape is against the edge — the
/// idle handle, or the compact Icon Strip, which occupy the window the same way.
///
/// Deliberately geometric: it reports *where* along the shape the pointer is and leaves
/// *what is there* to the caller, because the answer differs by state — chips while
/// closed, widget icons on an open strip.
#[derive(Debug, Clone, Copy, PartialEq)]
enum Zone {
    /// On the shape itself, this far along it from its leading end.
    OnShape(f64),
    /// On the popover beside it. Reading one must not be mistaken for the push that
    /// opens the panel, so this holds what is showing and does nothing else.
    Popover,
    /// Inside the window but past the shape, further from the screen edge. Pushing
    /// here is the deliberate gesture that opens the panel.
    Inward,
    Away,
}

/// Where the pointer sits relative to the shape drawn inside the panel window.
///
/// The window rect alone stopped being enough once a popover could enlarge it: the
/// window is the open size while the pointer is merely resting on the strip, so
/// "inside the window" would mean "open the panel" the instant a popover appeared.
/// The shape's own rectangle comes from the metrics the frontend was handed, which is
/// the same shape it drew.
#[allow(clippy::too_many_arguments)]
fn zone_of(
    pointer_x: f64,
    pointer_y: f64,
    origin_x: f64,
    origin_y: f64,
    scale: f64,
    metrics: &crate::geometry::PanelMetrics,
    edge: ScreenEdge,
    showing_popover: bool,
) -> Zone {
    // The handle's rectangle in screen coordinates.
    let left = origin_x + metrics.offset_x * scale;
    let top = origin_y + metrics.offset_y * scale;
    let right = left + metrics.shape_width * scale;
    let bottom = top + metrics.shape_height * scale;
    let slack = HOVER_BUFFER * scale;

    let on_strip = pointer_x >= left - slack
        && pointer_x < right + slack
        && pointer_y >= top - slack
        && pointer_y < bottom + slack;

    if on_strip {
        // Contents run along the shape: down it on the side edges, across it on the
        // top and bottom. The offset is measured from the same end Rust laid them from.
        let along = if edge.grows_horizontally() {
            (pointer_y - top) / scale
        } else {
            (pointer_x - left) / scale
        };
        return Zone::OnShape(along);
    }

    // How far past the shape the pointer has travelled, inward from the docked edge.
    let past = match edge {
        ScreenEdge::Trailing => (left - slack) - pointer_x,
        ScreenEdge::Leading => pointer_x - (right + slack),
        ScreenEdge::Top => pointer_y - (bottom + slack),
        ScreenEdge::Bottom => (top - slack) - pointer_y,
    } / scale;

    if past < 0.0 {
        return Zone::Away;
    }
    // The popover occupies the room immediately past the strip. Only beyond it is the
    // movement unambiguously "open the panel" rather than "let me read that".
    // `past` is measured from the far side of the buffer, and so is the popover.
    if showing_popover && past <= popover_offset() - HOVER_BUFFER + metrics.popover_width {
        Zone::Popover
    } else {
        Zone::Inward
    }
}

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
            let mut resting_since: Option<std::time::Instant> = None;

            while !flag.load(Ordering::Relaxed) {
                std::thread::sleep(POLL);

                let Some(window) = app.get_webview_window(panel::PANEL_LABEL) else { continue };
                let Ok(pointer) = app.cursor_position() else { continue };
                let (Ok(origin), Ok(size)) = (window.outer_position(), window.outer_size()) else {
                    continue;
                };
                let scale = window.scale_factor().unwrap_or(1.0);

                let inside = pointer.x >= origin.x as f64
                    && pointer.x < origin.x as f64 + size.width as f64
                    && pointer.y >= origin.y as f64
                    && pointer.y < origin.y as f64 + size.height as f64;

                let Some((expanded, popover, settings, snapshot)) = panel::with_state(&app, |state| {
                    (
                        state.expanded,
                        state.popover.clone(),
                        state.settings.clone(),
                        state.last_snapshot.clone(),
                    )
                }) else {
                    continue;
                };
                let hover_mode = settings.activation == ActivationMode::Hover;

                let zone = snapshot
                    .as_ref()
                    .filter(|_| inside)
                    .map(|snap| {
                        zone_of(
                            pointer.x,
                            pointer.y,
                            origin.x as f64,
                            origin.y as f64,
                            scale,
                            &snap.metrics,
                            settings.edge,
                            popover.is_some(),
                        )
                    })
                    .unwrap_or(Zone::Away);

                // Setting a popover is the same request wherever it comes from, so both
                // branches below go through this rather than repeating the plumbing.
                let show = |target: Option<Popover>| {
                    if popover == target || panel::hover_suppressed(&app) {
                        return;
                    }
                    let handle = app.clone();
                    let _ = app.run_on_main_thread(move || {
                        panel::set_popover(&handle, target);
                    });
                };

                if expanded {
                    inside_since = None;
                    if inside {
                        outside_since = None;
                        // Resting on a Row opens its Popover.
                        //
                        // Deliberately not gated on the activation mode: that setting
                        // decides whether the Panel may open by accident, and the Strip
                        // is only ever on screen because it was opened on purpose.
                        match zone {
                            Zone::OnShape(along) => {
                                let spans = row_spans(&settings);
                                match row_at(&spans, along) {
                                    Some(StripRow::Widget(id)) => {
                                        let id = id.clone();
                                        let since = *resting_since
                                            .get_or_insert_with(std::time::Instant::now);
                                        if since.elapsed().as_secs_f64() >= POPOVER_DELAY {
                                            show(Some(Popover::Widget(id)));
                                        }
                                    }
                                    // The settings Row and the gaps between Rows show
                                    // nothing, so sliding along the Strip past them puts
                                    // the last Popover away rather than stranding it.
                                    _ => {
                                        resting_since = None;
                                        show(None);
                                    }
                                }
                            }
                            // Reading the popover holds it; anywhere else in the
                            // window is the pointer on its way out.
                            Zone::Popover => resting_since = None,
                            _ => {
                                resting_since = None;
                                show(None);
                            }
                        }
                        continue;
                    }
                    resting_since = None;
                    let since = *outside_since.get_or_insert_with(std::time::Instant::now);
                    if !panel::holds_panel_open(&app)
                        && since.elapsed().as_secs_f64() >= settings.close_delay
                    {
                        let handle = app.clone();
                        let _ = app.run_on_main_thread(move || panel::close(&handle));
                    }
                    continue;
                }

                outside_since = None;
                let chip = match zone {
                    Zone::OnShape(along) => {
                        chip_at(&chip_spans(&settings, settings.enabled_slot_count()), along)
                    }
                    _ => None,
                };

                match zone {
                    // A reading with detail behind it: rest to see it, push past to open.
                    Zone::OnShape(_)
                        if hover_mode && chip.map(|chip| chip.draws_arc()).unwrap_or(false) =>
                    {
                        inside_since = None;
                        let since = *resting_since.get_or_insert_with(std::time::Instant::now);
                        if since.elapsed().as_secs_f64() >= POPOVER_DELAY {
                            show(chip.map(Popover::Chip));
                        }
                    }
                    // Anything else on the handle keeps the behaviour it always had:
                    // rest on it and the panel opens. Only readings that have something
                    // more to say ask for the extra push.
                    Zone::OnShape(_) => {
                        resting_since = None;
                        let since = *inside_since.get_or_insert_with(std::time::Instant::now);
                        if hover_mode
                            && since.elapsed().as_secs_f64() >= settings.open_delay
                            && !panel::hover_suppressed(&app)
                        {
                            let handle = app.clone();
                            let _ = app.run_on_main_thread(move || panel::open(&handle));
                        }
                    }
                    // Resting on the card: hold it, and neither open nor close.
                    Zone::Popover => {
                        resting_since = None;
                        inside_since = None;
                    }
                    Zone::Inward => {
                        resting_since = None;
                        inside_since = None;
                        if hover_mode && !panel::hover_suppressed(&app) {
                            let handle = app.clone();
                            let _ = app.run_on_main_thread(move || panel::open(&handle));
                        }
                    }
                    Zone::Away => {
                        resting_since = None;
                        inside_since = None;
                        show(None);
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

#[cfg(test)]
mod tests {
    use super::{zone_of, Zone};
    use crate::geometry::{
        chip_at, chip_spans, popover_offset, row_at, row_extent, row_spans, strip_depth,
        PanelMetrics, StripRow, POPOVER_GAP,
    };
    use crate::settings::{IdleChip, ScreenEdge, Settings};

    /// A handle 40 wide and 200 tall, sitting at the right of a 400-wide window whose
    /// top-left corner is the screen origin. Scale 1, so screen and logical agree.
    fn metrics() -> PanelMetrics {
        PanelMetrics {
            expanded: false,
            shape_width: 40.0,
            shape_height: 200.0,
            corner_radius: 13.0,
            inverse_radius: 9.0,
            shows_content: true,
            offset_x: 360.0,
            offset_y: 100.0,
            window_width: 400.0,
            window_height: 400.0,
            handle_ring: 30.0,
            popover_width: 236.0,
            popover_offset: popover_offset(),
            popover_height: 320.0,
            strip_row_extent: row_extent(true),
            strip_depth: strip_depth(true),
        }
    }

    fn settings() -> Settings {
        Settings {
            edge: ScreenEdge::Trailing,
            handle_chips: vec![IdleChip::Cpu, IdleChip::Memory],
            ..Default::default()
        }
    }

    fn zone(x: f64, y: f64, showing: bool) -> Zone {
        zone_of(x, y, 0.0, 0.0, 1.0, &metrics(), settings().edge, showing)
    }

    /// What the watchdog does with `OnShape` while the panel is closed.
    fn chip_under(x: f64, y: f64) -> Option<IdleChip> {
        match zone(x, y, false) {
            Zone::OnShape(along) => chip_at(&chip_spans(&settings(), 0), along),
            other => panic!("expected to be on the handle, got {other:?}"),
        }
    }

    #[test]
    fn the_strip_itself_reports_the_chip_under_the_pointer() {
        // Just inside the handle, a little way down from its top edge.
        assert_eq!(chip_under(380.0, 118.0), Some(IdleChip::Cpu));
    }

    /// And what it does with the same offset while the Strip is open.
    #[test]
    fn an_open_strip_reports_the_row_under_the_pointer() {
        let settings = settings();
        let spans = row_spans(&settings);
        // The Strip starts at the shape's top edge; the first Row is the settings
        // action, so the second is the first enabled widget.
        let second = spans[1].start + row_extent(true) / 2.0;
        match zone_of(380.0, 100.0 + second, 0.0, 0.0, 1.0, &metrics(), settings.edge, false) {
            Zone::OnShape(along) => {
                assert_eq!(row_at(&spans, along), Some(&StripRow::Widget("clock".into())))
            }
            other => panic!("expected to be on the strip, got {other:?}"),
        }
    }

    #[test]
    fn reaching_over_to_read_a_card_does_not_open_the_panel() {
        // Where the card is drawn: just past the strip, inward from the right edge.
        let onto_the_card = 360.0 - super::HOVER_BUFFER - POPOVER_GAP - 20.0;
        assert_eq!(zone(onto_the_card, 200.0, true), Zone::Popover);
    }

    #[test]
    fn the_near_edge_of_a_popover_is_not_the_handle() {
        // Reaching for a popover must not read as still being on the handle, which
        // would put it away in the same motion that reached for it.
        let near_edge = 360.0 - popover_offset() + 0.5;
        assert_eq!(zone(near_edge, 200.0, true), Zone::Popover);
    }

    #[test]
    fn the_same_spot_opens_the_panel_when_no_card_is_showing() {
        let onto_the_card = 360.0 - super::HOVER_BUFFER - POPOVER_GAP - 20.0;
        assert_eq!(zone(onto_the_card, 200.0, false), Zone::Inward);
    }

    #[test]
    fn pushing_past_the_card_opens_the_panel() {
        let beyond = 360.0 - super::HOVER_BUFFER - POPOVER_GAP - metrics().popover_width - 10.0;
        assert_eq!(zone(beyond, 200.0, true), Zone::Inward);
    }

    #[test]
    fn the_far_side_of_the_handle_is_neither_a_push_nor_a_rest() {
        // Off the top of the strip: along the edge, not inward from it.
        assert_eq!(zone(380.0, 10.0, true), Zone::Away);
    }

    /// The push is measured from whichever edge the panel is docked to.
    #[test]
    fn inward_follows_the_docked_edge() {
        let s = Settings { edge: ScreenEdge::Leading, ..settings() };
        let mut m = metrics();
        m.offset_x = 0.0;
        // Leading dock: inward means a larger x, the opposite of trailing.
        let pushed = zone_of(40.0 + super::HOVER_BUFFER + 5.0, 200.0, 0.0, 0.0, 1.0, &m, s.edge, false);
        assert_eq!(pushed, Zone::Inward);
    }
}

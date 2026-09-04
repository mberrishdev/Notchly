//! Turns settings plus a display into concrete window frames.
//!
//! Ported from the Swift implementation, with one simplification: Tauri reports monitor
//! coordinates with the origin at the top left, where Cocoa used the bottom left. That
//! removes the axis flip the Swift version needed, so alignment reads the same way on
//! every edge — 0 is always top or left.

use crate::settings::{IdleChip, ScreenEdge, Settings};
use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

impl Rect {
    pub fn new(x: f64, y: f64, width: f64, height: f64) -> Self {
        Self { x, y, width, height }
    }
    pub fn max_x(&self) -> f64 {
        self.x + self.width
    }
    pub fn max_y(&self) -> f64 {
        self.y + self.height
    }
}

/// Size of the idle handle for a given set of chips.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct HandleLayout {
    /// How far the handle protrudes from the edge.
    pub depth: f64,
    /// How far it runs along the edge.
    pub extent: f64,
    /// False when there are no chips, i.e. the plain line.
    pub shows_content: bool,
    /// Diameter of the arc a reading draws. Kept here because it is what the chips were
    /// measured against — the frontend is handed this number rather than deriving its
    /// own, so the handle's size and its contents cannot disagree.
    pub ring: f64,
}

pub const CHIP_SPACING: f64 = 5.0;
pub const CHIP_END_PADDING: f64 = 9.0;
/// Room reserved around the open panel for its drop shadow.
pub const SHADOW_MARGIN: f64 = 34.0;
/// The popover's own footprint. The frontend is handed the width rather than choosing
/// it, because the hover zones have to know exactly where the card is: reaching over to
/// read one must not be mistaken for the push that opens the panel.
pub const POPOVER_GAP: f64 = 10.0;

/// The Strip's own dimensions, per orientation.
///
/// Fixed rather than set by the user: every Row reserves the same room whether or not
/// its reading currently has a value, for the reason an Idle Chip does — a Strip that
/// resized itself when a song started would move the drag target out from under the
/// pointer. The two orientations differ because a Row lays its value beside the glyph on
/// the side edges and under it on the top and bottom.
///
/// `grows_horizontally` is true on the left and right edges, where Rows stack in a
/// column: the Strip's depth is then the width a value like `15:32` needs, and a Row's
/// extent is its height.
pub fn strip_depth(grows_horizontally: bool) -> f64 {
    // Wide enough for the longest reading a Row shows — `13:03`, `100%` — beside its
    // glyph, with the end padding the Rows are laid out with still clear on both sides.
    if grows_horizontally { 66.0 } else { 38.0 }
}

pub fn row_extent(grows_horizontally: bool) -> f64 {
    if grows_horizontally { 26.0 } else { 62.0 }
}

/// The flare at each end of the Strip, which the Rows have to start clear of.
///
/// A free function because `row_spans` needs it without a `PanelGeometry` in hand.
pub fn strip_inverse_radius(grows_horizontally: bool) -> f64 {
    (strip_depth(grows_horizontally) * 0.3).min(9.0)
}

/// Slack around the idle handle so the pointer doesn't need pixel precision.
pub const HOVER_BUFFER: f64 = 22.0;

/// How far from the shape a popover is actually drawn.
///
/// Clear of the hover buffer, not merely of the shape: the buffer is treated as part of
/// the handle, so a card drawn inside it had a near edge that read as "still on the
/// handle" — which put the card away again the moment the pointer reached for it.
pub fn popover_offset() -> f64 {
    HOVER_BUFFER + POPOVER_GAP
}

impl HandleLayout {
    /// `shows_handle_when_idle` is what makes Notchly disappear: it leaves the bare
    /// line without touching the chips the user picked, so turning it back on restores
    /// the strip they had rather than an empty one.
    pub fn resolve(settings: &Settings, widget_count: usize) -> Self {
        if !settings.shows_handle_when_idle || settings.handle_chips.is_empty() {
            return Self {
                depth: settings.handle_thickness.max(2.0),
                extent: settings.handle_length.max(12.0),
                shows_content: false,
                ring: 0.0,
            };
        }
        let horizontal = settings.edge.grows_horizontally();
        let ring = crate::settings::ring_diameter(settings.handle_content_thickness);
        let content: f64 = settings
            .handle_chips
            .iter()
            .map(|chip| chip.extent(horizontal, widget_count, ring))
            .sum();
        let gaps = CHIP_SPACING * settings.handle_chips.len().saturating_sub(1) as f64;
        Self {
            depth: settings.handle_content_thickness.max(18.0),
            extent: (content + gaps + CHIP_END_PADDING * 2.0).max(28.0),
            shows_content: true,
            ring,
        }
    }
}

/// Where one chip sits along the handle: its start offset from the handle's leading
/// end, and how much room it takes.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ChipSpan {
    pub chip: IdleChip,
    pub start: f64,
    pub length: f64,
}

/// Lays the chips out along the handle.
///
/// The frontend arranges the same chips with the same gaps, but only Rust needs to
/// answer "which one is the pointer on" — the web view cannot be asked, because a
/// non-activating panel does not deliver reliable pointer events. So the arithmetic
/// lives here, beside the sizing it has to agree with.
pub fn chip_spans(settings: &Settings, widget_count: usize) -> Vec<ChipSpan> {
    let horizontal = settings.edge.grows_horizontally();
    let ring = crate::settings::ring_diameter(settings.handle_content_thickness);
    let mut spans = Vec::with_capacity(settings.handle_chips.len());
    let mut cursor = CHIP_END_PADDING;
    for chip in &settings.handle_chips {
        let length = chip.extent(horizontal, widget_count, ring);
        spans.push(ChipSpan { chip: *chip, start: cursor, length });
        cursor += length + CHIP_SPACING;
    }
    spans
}

/// The chip at `offset` along the handle, if the pointer is on one at all.
///
/// The gaps between chips deliberately belong to no chip: sliding across the strip
/// should not flicker a popover through every reading on the way past.
pub fn chip_at(spans: &[ChipSpan], offset: f64) -> Option<IdleChip> {
    spans
        .iter()
        .find(|span| offset >= span.start && offset < span.start + span.length)
        .map(|span| span.chip)
}

/// One Row on the Strip.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StripRow {
    /// Opens the settings window. Always first, so its position never moves as widgets
    /// are added and removed.
    Settings,
    Widget(String),
}

#[derive(Debug, Clone, PartialEq)]
pub struct RowSpan {
    pub row: StripRow,
    pub start: f64,
    pub length: f64,
}

/// Size of the Strip: the settings action plus one Row per enabled Slot.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct StripLayout {
    pub depth: f64,
    pub extent: f64,
    /// A single Row's room along the edge. Handed to the frontend so the boxes it draws
    /// and the spans Rust tests the pointer against are the same size.
    pub row: f64,
}

impl StripLayout {
    pub fn resolve(settings: &Settings) -> Self {
        let horizontal = settings.edge.grows_horizontally();
        let rows = settings.enabled_slot_count() + 1;
        let each = row_extent(horizontal);
        let gaps = CHIP_SPACING * rows.saturating_sub(1) as f64;
        Self {
            depth: strip_depth(horizontal),
            extent: rows as f64 * each + gaps + CHIP_END_PADDING * 2.0,
            row: each,
        }
    }
}

/// Lays the Rows out along the Strip.
///
/// The same reason `chip_spans` lives here: only Rust can answer "which Row is the
/// pointer on", because the panel never activates and so cannot rely on the web view
/// receiving pointer events.
pub fn row_spans(settings: &Settings) -> Vec<RowSpan> {
    let horizontal = settings.edge.grows_horizontally();
    let each = row_extent(horizontal);
    let mut spans = Vec::with_capacity(settings.enabled_slot_count() + 1);
    // Offsets are measured from the leading end of the drawn shape, flare included,
    // because that is the rectangle the pointer is tested against.
    let mut cursor = strip_inverse_radius(horizontal) + CHIP_END_PADDING;
    let mut push = |row: StripRow, cursor: &mut f64| {
        spans.push(RowSpan { row, start: *cursor, length: each });
        *cursor += each + CHIP_SPACING;
    };
    push(StripRow::Settings, &mut cursor);
    for slot in settings.slots.iter().filter(|slot| slot.is_enabled) {
        push(StripRow::Widget(slot.widget_id.clone()), &mut cursor);
    }
    spans
}

/// The Row at `offset` along the Strip. As with the chips, the gaps belong to no Row, so
/// sliding along the Strip does not flash a Popover for every widget on the way.
pub fn row_at(spans: &[RowSpan], offset: f64) -> Option<&StripRow> {
    spans
        .iter()
        .find(|span| offset >= span.start && offset < span.start + span.length)
        .map(|span| &span.row)
}

/// The Strip's drawn shape, with no display involved.
///
/// Its size falls out of the settings alone — only *where* it sits needs a screen — so
/// the Settings window can model it without one, and without a second implementation of
/// the arithmetic.
#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StripPreview {
    /// How far it protrudes from the edge, and how far it runs along it. Both are the
    /// drawn shape, so the extent includes the flare at each end.
    pub depth: f64,
    pub extent: f64,
    pub corner_radius: f64,
    pub inverse_radius: f64,
}

impl StripPreview {
    pub fn resolve(settings: &Settings) -> Self {
        let horizontal = settings.edge.grows_horizontally();
        let strip = StripLayout::resolve(settings);
        let inverse = strip_inverse_radius(horizontal);
        Self {
            depth: strip.depth,
            extent: strip.extent + 2.0 * inverse,
            corner_radius: (strip.depth / 2.0).min(13.0),
            inverse_radius: inverse,
        }
    }
}

/// Where the panel should dock for a given pointer position.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Placement {
    pub edge: ScreenEdge,
    /// 0 is the top or left of the display, 1 the bottom or right.
    pub alignment: f64,
}

impl Placement {
    pub fn resolve(pointer_x: f64, pointer_y: f64, screen: Rect) -> Option<Self> {
        if screen.width <= 0.0 || screen.height <= 0.0 {
            return None;
        }
        // Distances are normalised by the screen's own dimensions, so on a wide display
        // the left and right edges still win inside their own halves rather than the
        // top and bottom claiming almost everything.
        let candidates = [
            (ScreenEdge::Leading, (pointer_x - screen.x) / screen.width),
            (ScreenEdge::Trailing, (screen.max_x() - pointer_x) / screen.width),
            (ScreenEdge::Top, (pointer_y - screen.y) / screen.height),
            (ScreenEdge::Bottom, (screen.max_y() - pointer_y) / screen.height),
        ];
        let edge = candidates
            .iter()
            .min_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))?
            .0;

        let alignment = if edge.grows_horizontally() {
            (pointer_y - screen.y) / screen.height
        } else {
            (pointer_x - screen.x) / screen.width
        };
        Some(Self {
            edge,
            alignment: alignment.clamp(0.0, 1.0),
        })
    }
}

/// Everything the frontend needs to draw the panel, and the frame the window needs.
#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PanelMetrics {
    pub expanded: bool,
    /// Size of the drawn shape, including the concave flares.
    pub shape_width: f64,
    pub shape_height: f64,
    pub corner_radius: f64,
    pub inverse_radius: f64,
    pub shows_content: bool,
    /// Offset of the shape inside the window, leaving room for the shadow.
    pub offset_x: f64,
    pub offset_y: f64,
    /// Size of the window these offsets are relative to.
    ///
    /// During a close the window is still at its open size while the shape is already
    /// collapsed, so the frontend cannot infer this from its own dimensions — it has
    /// to be told which window the offsets belong to.
    pub window_width: f64,
    pub window_height: f64,
    /// Diameter of the arc an idle reading draws. Computed here so the size the handle
    /// was measured against and the size the frontend paints cannot drift apart.
    pub handle_ring: f64,
    /// How wide the popover is drawn. Same reason: the hover zones depend on it.
    pub popover_width: f64,
    /// How far from the shape it is drawn, for the same reason again.
    pub popover_offset: f64,
    /// How tall a popover may grow before its content scrolls. The window is only sized
    /// to hold this much, so a popover that ignored it would be clipped.
    pub popover_height: f64,
    /// One Strip Row's room along the edge, and the Strip's depth across it. Handed over
    /// for the same reason as `handle_ring`: Rust measured the Strip against these and
    /// decides what the pointer is on, so the frontend must not derive its own.
    pub strip_row_extent: f64,
    pub strip_depth: f64,
}

pub struct PanelGeometry {
    pub edge: ScreenEdge,
    pub screen: Rect,
    pub alignment: f64,
    pub handle: HandleLayout,
    pub strip: StripLayout,
    pub popover_width: f64,
    pub popover_height: f64,
    pub edge_inset: f64,
}

impl PanelGeometry {
    pub fn new(settings: &Settings, screen: Rect, widget_count: usize) -> Self {
        Self {
            edge: settings.edge,
            screen,
            alignment: settings.alignment,
            handle: HandleLayout::resolve(settings, widget_count),
            strip: StripLayout::resolve(settings),
            popover_width: settings.popover_width,
            popover_height: settings.popover_height,
            edge_inset: settings.edge_inset,
        }
    }

    pub fn handle_inverse_radius(&self) -> f64 {
        if self.handle.shows_content {
            (self.handle.depth * 0.3).min(9.0)
        } else {
            (self.handle.depth * 1.2).min(6.0)
        }
    }

    pub fn handle_corner_radius(&self) -> f64 {
        if self.handle.shows_content {
            (self.handle.depth / 2.0).min(13.0)
        } else {
            (self.handle.depth / 2.0 + 2.0).min(6.0)
        }
    }

    /// The Strip is shaped like a handle that shows content, because that is what it is
    /// — a strip against the bezel — rather than a small version of anything.
    pub fn strip_inverse_radius(&self) -> f64 {
        strip_inverse_radius(self.edge.grows_horizontally())
    }

    pub fn strip_corner_radius(&self) -> f64 {
        (self.strip.depth / 2.0).min(13.0)
    }

    fn depth(&self, expanded: bool) -> f64 {
        if expanded { self.strip.depth } else { self.handle.depth }
    }

    fn extent(&self, expanded: bool) -> f64 {
        if expanded { self.strip.extent } else { self.handle.extent }
    }

    fn inverse_radius(&self, expanded: bool) -> f64 {
        if expanded { self.strip_inverse_radius() } else { self.handle_inverse_radius() }
    }

    fn margin(&self, expanded: bool) -> f64 {
        if expanded { SHADOW_MARGIN } else { HOVER_BUFFER }
    }

    /// Room a Popover needs beside the shape, in depth and along the edge.
    ///
    /// Only the open window reserves it. The idle window stays snug around the Handle,
    /// because an always-large transparent window would swallow clicks meant for the
    /// desktop — and an Idle Chip's Popover does not need the reserve here, since
    /// showing one already puts the window at its open size.
    fn popover_reserve(&self, expanded: bool) -> (f64, f64) {
        if expanded {
            (popover_offset() + self.popover_width, self.popover_height)
        } else {
            (0.0, 0.0)
        }
    }

    /// How deep and how long the window's contents are, before its margin.
    fn content_depth(&self, expanded: bool) -> f64 {
        self.depth(expanded) + self.popover_reserve(expanded).0
    }

    fn content_extent(&self, expanded: bool) -> f64 {
        (self.extent(expanded) + 2.0 * self.inverse_radius(expanded))
            .max(self.popover_reserve(expanded).1)
    }

    /// Centre of the panel along its edge, in display coordinates.
    ///
    /// Deliberately independent of open/closed: clamping with the idle handle's much
    /// smaller half-extent put the two states at different centres, so the panel slid
    /// along its edge as it opened. The open footprint is the binding constraint, so
    /// both states use it and the panel grows in place.
    pub fn edge_center(&self) -> f64 {
        // Whichever state is longer sets the clamp. In the full style that is always the
        // open panel, but a compact strip can be shorter than the handle beside it.
        let content = self.content_extent(true).max(self.content_extent(false));
        let half = content / 2.0 + self.margin(true);
        let (lo, hi) = if self.edge.grows_horizontally() {
            (self.screen.y + half, self.screen.max_y() - half)
        } else {
            (self.screen.x + half, self.screen.max_x() - half)
        };
        if hi <= lo {
            return if self.edge.grows_horizontally() {
                self.screen.y + self.screen.height / 2.0
            } else {
                self.screen.x + self.screen.width / 2.0
            };
        }
        lo + self.alignment * (hi - lo)
    }

    pub fn window_frame(&self, expanded: bool) -> Rect {
        let margin = self.margin(expanded);
        let depth = self.content_depth(expanded) + margin;
        let extent = self.content_extent(expanded) + 2.0 * margin;
        let center = self.edge_center();

        match self.edge {
            ScreenEdge::Trailing => Rect::new(
                self.screen.max_x() - depth + self.edge_inset,
                center - extent / 2.0,
                depth,
                extent,
            ),
            ScreenEdge::Leading => {
                Rect::new(self.screen.x - self.edge_inset, center - extent / 2.0, depth, extent)
            }
            ScreenEdge::Top => {
                Rect::new(center - extent / 2.0, self.screen.y - self.edge_inset, extent, depth)
            }
            ScreenEdge::Bottom => Rect::new(
                center - extent / 2.0,
                self.screen.max_y() - depth + self.edge_inset,
                extent,
                depth,
            ),
        }
    }

    /// Metrics for `expanded`, positioned inside the window sized for `window_state`.
    pub fn metrics_in(&self, expanded: bool, window_state: bool) -> PanelMetrics {
        let inverse = self.inverse_radius(expanded);
        let depth = self.depth(expanded);
        let extent = self.extent(expanded) + 2.0 * inverse;

        let (shape_width, shape_height) = if self.edge.grows_horizontally() {
            (depth, extent)
        } else {
            (extent, depth)
        };

        let window = self.window_frame(window_state);
        // Hug the docked edge of whichever window is currently applied.
        let (offset_x, offset_y) = match self.edge {
            ScreenEdge::Trailing => (window.width - shape_width, (window.height - shape_height) / 2.0),
            ScreenEdge::Leading => (0.0, (window.height - shape_height) / 2.0),
            ScreenEdge::Top => ((window.width - shape_width) / 2.0, 0.0),
            ScreenEdge::Bottom => ((window.width - shape_width) / 2.0, window.height - shape_height),
        };

        PanelMetrics {
            expanded,
            shape_width,
            shape_height,
            corner_radius: if expanded {
                self.strip_corner_radius()
            } else {
                self.handle_corner_radius()
            },
            inverse_radius: inverse,
            shows_content: expanded || self.handle.shows_content,
            offset_x,
            offset_y,
            window_width: window.width,
            window_height: window.height,
            handle_ring: self.handle.ring,
            popover_width: self.popover_width,
            popover_offset: popover_offset(),
            popover_height: self.popover_height,
            strip_row_extent: self.strip.row,
            strip_depth: self.strip.depth,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::settings::{ActivationMode, IdleChip};

    fn screen() -> Rect {
        Rect::new(0.0, 0.0, 1512.0, 982.0)
    }

    fn settings(edge: ScreenEdge, alignment: f64) -> Settings {
        Settings {
            edge,
            alignment,
            handle_thickness: 5.0,
            handle_length: 108.0,
            handle_chips: Vec::new(),
            activation: ActivationMode::Hover,
            ..Default::default()
        }
    }

    fn geometry(edge: ScreenEdge, alignment: f64) -> PanelGeometry {
        PanelGeometry::new(&settings(edge, alignment), screen(), 5)
    }

    #[test]
    fn open_frame_is_flush_with_its_docked_edge() {
        let s = screen();
        assert!((geometry(ScreenEdge::Trailing, 0.5).window_frame(true).max_x() - s.max_x()).abs() < 0.001);
        assert!((geometry(ScreenEdge::Leading, 0.5).window_frame(false).x - s.x).abs() < 0.001);
        assert!((geometry(ScreenEdge::Top, 0.5).window_frame(true).y - s.y).abs() < 0.001);
        assert!((geometry(ScreenEdge::Bottom, 0.5).window_frame(false).max_y() - s.max_y()).abs() < 0.001);
    }

    #[test]
    fn idle_frame_is_much_smaller_than_the_open_one() {
        // Shrinking the window when closed is what stops Notchly intercepting clicks
        // meant for the desktop.
        let g = geometry(ScreenEdge::Trailing, 0.5);
        let idle = g.window_frame(false);
        let open = g.window_frame(true);
        assert!(idle.width * idle.height < open.width * open.height / 8.0);
    }

    #[test]
    fn alignment_zero_is_top_for_side_edges_and_left_for_top_and_bottom() {
        assert!(
            geometry(ScreenEdge::Trailing, 0.0).edge_center()
                < geometry(ScreenEdge::Trailing, 1.0).edge_center()
        );
        assert!(
            geometry(ScreenEdge::Top, 0.0).edge_center() < geometry(ScreenEdge::Top, 1.0).edge_center()
        );
    }

    #[test]
    fn panel_never_hangs_off_the_ends_of_its_edge() {
        for alignment in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let frame = geometry(ScreenEdge::Trailing, alignment).window_frame(true);
            assert!(frame.y >= screen().y - 0.001, "alignment {alignment}");
            assert!(frame.max_y() <= screen().max_y() + 0.001, "alignment {alignment}");
        }
    }

    #[test]
    fn the_strip_turns_with_its_edge_rather_than_keeping_one_orientation() {
        // Rows stack down the side edges and run along the top and bottom, so the strip
        // is deep and short on one and shallow and long on the other.
        let side = StripLayout::resolve(&settings(ScreenEdge::Trailing, 0.5));
        let top = StripLayout::resolve(&settings(ScreenEdge::Top, 0.5));
        assert!(side.depth > top.depth);
        assert!(side.extent < top.extent);
    }

    #[test]
    fn each_corner_region_picks_the_edge_you_would_expect() {
        let wide = Rect::new(0.0, 0.0, 3440.0, 1440.0);
        let edge = |x, y| Placement::resolve(x, y, wide).map(|p| p.edge);
        assert_eq!(edge(40.0, 720.0), Some(ScreenEdge::Leading));
        assert_eq!(edge(3400.0, 720.0), Some(ScreenEdge::Trailing));
        assert_eq!(edge(1720.0, 20.0), Some(ScreenEdge::Top));
        assert_eq!(edge(1720.0, 1420.0), Some(ScreenEdge::Bottom));
    }

    #[test]
    fn side_edges_win_inside_their_own_half_of_a_wide_display() {
        // In raw points a pointer 500px from the left of an ultrawide is "closer" to the
        // top; normalising per dimension is what makes dragging left actually dock left.
        let wide = Rect::new(0.0, 0.0, 3440.0, 1440.0);
        assert_eq!(
            Placement::resolve(500.0, 720.0, wide).map(|p| p.edge),
            Some(ScreenEdge::Leading)
        );
    }

    #[test]
    fn placement_is_clamped_and_rejects_a_degenerate_screen() {
        let wide = Rect::new(0.0, 0.0, 3440.0, 1440.0);
        let past = Placement::resolve(-50.0, 5000.0, wide).unwrap();
        assert!((0.0..=1.0).contains(&past.alignment));
        assert!(Placement::resolve(0.0, 0.0, Rect::new(0.0, 0.0, 0.0, 0.0)).is_none());
    }

    #[test]
    fn placement_works_on_a_display_whose_origin_is_not_zero() {
        let offset = Rect::new(-1710.0, 1112.0, 1710.0, 1112.0);
        let placement = Placement::resolve(-1700.0, 1668.0, offset).unwrap();
        assert_eq!(placement.edge, ScreenEdge::Leading);
        assert!((placement.alignment - 0.5).abs() < 0.02);
    }

    #[test]
    fn no_chips_gives_the_plain_line_at_the_configured_size() {
        let line = HandleLayout::resolve(&settings(ScreenEdge::Trailing, 0.5), 5);
        assert!(!line.shows_content);
        assert_eq!((line.depth, line.extent), (5.0, 108.0));
    }

    #[test]
    fn chips_switch_to_the_content_thickness_and_grow_with_each_one() {
        let mut s = settings(ScreenEdge::Trailing, 0.5);
        s.handle_chips = vec![IdleChip::Clock];
        let one = HandleLayout::resolve(&s, 5);
        assert!(one.shows_content);
        // The configured thickness, not a number this test happens to know.
        assert_eq!(one.depth, s.handle_content_thickness);

        s.handle_chips = vec![IdleChip::Clock, IdleChip::NowPlaying];
        assert!(HandleLayout::resolve(&s, 5).extent > one.extent);
    }

    #[test]
    fn chips_are_laid_out_end_to_end_with_a_gap_between() {
        let mut s = settings(ScreenEdge::Trailing, 0.5);
        s.handle_chips = vec![IdleChip::Clock, IdleChip::Cpu];
        let spans = chip_spans(&s, 0);

        assert_eq!(spans.len(), 2);
        assert_eq!(spans[0].start, CHIP_END_PADDING);
        assert_eq!(spans[1].start, spans[0].start + spans[0].length + CHIP_SPACING);
    }

    #[test]
    fn the_pointer_finds_the_chip_it_is_on() {
        let mut s = settings(ScreenEdge::Trailing, 0.5);
        s.handle_chips = vec![IdleChip::Clock, IdleChip::Cpu];
        let spans = chip_spans(&s, 0);

        let middle_of_first = spans[0].start + spans[0].length / 2.0;
        let middle_of_second = spans[1].start + spans[1].length / 2.0;
        assert_eq!(chip_at(&spans, middle_of_first), Some(IdleChip::Clock));
        assert_eq!(chip_at(&spans, middle_of_second), Some(IdleChip::Cpu));
    }

    /// Sliding down the strip must not flash a popover through every reading on the way.
    #[test]
    fn the_gaps_between_chips_belong_to_no_chip() {
        let mut s = settings(ScreenEdge::Trailing, 0.5);
        s.handle_chips = vec![IdleChip::Clock, IdleChip::Cpu];
        let spans = chip_spans(&s, 0);

        let in_the_gap = spans[0].start + spans[0].length + CHIP_SPACING / 2.0;
        assert_eq!(chip_at(&spans, in_the_gap), None);
        assert_eq!(chip_at(&spans, 0.0), None, "the end padding is not a chip");
        assert_eq!(chip_at(&spans, 10_000.0), None, "past the end is not a chip");
    }

    #[test]
    fn a_handle_with_no_chips_has_nothing_to_point_at() {
        let s = settings(ScreenEdge::Trailing, 0.5);
        assert!(chip_spans(&s, 0).is_empty());
    }

    #[test]
    fn an_arc_chip_grows_with_the_ring_it_draws() {
        let mut thin = settings(ScreenEdge::Trailing, 0.5);
        thin.handle_chips = vec![IdleChip::Cpu];
        thin.handle_content_thickness = 24.0;
        let mut thick = thin.clone();
        thick.handle_content_thickness = 44.0;

        let small = HandleLayout::resolve(&thin, 0);
        let large = HandleLayout::resolve(&thick, 0);
        assert!(small.ring < large.ring, "{} !< {}", small.ring, large.ring);
        assert!(small.extent < large.extent, "a smaller ring should need less room");
    }

    /// A handle someone has already made thin must still hold its readings.
    #[test]
    fn the_ring_never_outgrows_the_handle_it_sits_in() {
        for thickness in [18.0, 24.0, 30.0, 44.0, 90.0] {
            let ring = crate::settings::ring_diameter(thickness);
            assert!(ring <= thickness, "ring {ring} does not fit in {thickness}");
            assert!(ring >= 18.0, "ring {ring} is too small to read");
        }
    }

    #[test]
    fn a_plain_line_draws_no_ring() {
        let line = HandleLayout::resolve(&settings(ScreenEdge::Trailing, 0.5), 5);
        assert_eq!(line.ring, 0.0);
    }

    #[test]
    fn handle_extent_accounts_for_spacing_between_chips() {
        let mut s = settings(ScreenEdge::Trailing, 0.5);
        s.handle_chips = vec![IdleChip::Clock, IdleChip::Cpu, IdleChip::Battery];
        let ring = crate::settings::ring_diameter(s.handle_content_thickness);
        let content: f64 = s.handle_chips.iter().map(|c| c.extent(true, 5, ring)).sum();
        let expected = content + CHIP_SPACING * 2.0 + CHIP_END_PADDING * 2.0;
        assert!((HandleLayout::resolve(&s, 5).extent - expected).abs() < 0.001);
    }

    #[test]
    fn the_shape_hugs_the_docked_edge_of_its_window() {
        for (edge, probe) in [
            (ScreenEdge::Trailing, 0),
            (ScreenEdge::Leading, 1),
            (ScreenEdge::Top, 2),
            (ScreenEdge::Bottom, 3),
        ] {
            let g = geometry(edge, 0.5);
            let m = g.metrics_in(true, true);
            match probe {
                0 => assert!((m.offset_x + m.shape_width - m.window_width).abs() < 0.001),
                1 => assert!(m.offset_x.abs() < 0.001),
                2 => assert!(m.offset_y.abs() < 0.001),
                _ => assert!((m.offset_y + m.shape_height - m.window_height).abs() < 0.001),
            }
        }
    }

    #[test]
    fn the_panel_grows_in_place_rather_than_sliding_along_its_edge() {
        // Both states must share a centre, or opening visibly slides the panel.
        for edge in [ScreenEdge::Trailing, ScreenEdge::Leading, ScreenEdge::Top, ScreenEdge::Bottom] {
            let g = geometry(edge, 0.42);
            let idle = g.window_frame(false);
            let open = g.window_frame(true);
            let (idle_centre, open_centre) = if edge.grows_horizontally() {
                (idle.y + idle.height / 2.0, open.y + open.height / 2.0)
            } else {
                (idle.x + idle.width / 2.0, open.x + open.width / 2.0)
            };
            assert!((idle_centre - open_centre).abs() < 0.001, "{edge:?} slid on open");
        }
    }

    #[test]
    fn a_collapsing_panel_is_positioned_in_the_window_it_is_still_in() {
        // Mid-close the window has not shrunk yet, so the collapsed shape must be
        // placed against the *open* window's edge or it visibly jumps.
        let g = geometry(ScreenEdge::Trailing, 0.5);
        let during = g.metrics_in(false, true);
        let after = g.metrics_in(false, false);
        assert!((during.offset_x + during.shape_width - during.window_width).abs() < 0.001);
        assert!(during.window_width > after.window_width);
        assert_eq!(during.shape_width, after.shape_width);
    }

    #[test]
    fn hiding_the_handle_leaves_the_bare_line_without_forgetting_the_chips() {
        let chosen = vec![IdleChip::Clock, IdleChip::Cpu];
        let shown = Settings {
            handle_chips: chosen.clone(),
            shows_handle_when_idle: true,
            ..Default::default()
        };
        let hidden = Settings { shows_handle_when_idle: false, ..shown.clone() };

        assert!(HandleLayout::resolve(&shown, 5).shows_content);
        let line = HandleLayout::resolve(&hidden, 5);
        assert!(!line.shows_content);
        assert_eq!(line.depth, hidden.handle_thickness);
        // The chips survive the round trip, so turning it back on restores the strip.
        assert_eq!(hidden.handle_chips, chosen);
    }

    #[test]
    fn the_open_panel_is_a_strip_barely_larger_than_the_handle() {
        // The Strip is the whole Open state now: it must stay a strip against the bezel
        // rather than drift back towards a surface with a footprint.
        let g = geometry(ScreenEdge::Trailing, 0.5);
        let strip = g.metrics_in(true, true);
        assert!(strip.shape_width <= strip_depth(true) + 1.0);
        // Deep enough for a reading beside its glyph, which is the point of a Row.
        assert!(strip.shape_width > 40.0);
    }

    #[test]
    fn a_row_is_deeper_on_the_side_edges_where_its_value_sits_beside_the_glyph() {
        assert!(strip_depth(true) > strip_depth(false));
        // And shorter along the edge, because a column of rows stacks rather than runs.
        assert!(row_extent(true) < row_extent(false));
    }

    #[test]
    fn the_window_reserves_room_for_a_popover_beside_the_strip() {
        // Without the reserve a popover would be drawn outside the window and clipped.
        let g = geometry(ScreenEdge::Trailing, 0.5);
        let open = g.window_frame(true);
        let strip = g.metrics_in(true, true);
        assert!(open.width >= strip.shape_width + popover_offset() + g.popover_width);
        assert!(open.height >= g.popover_height);
    }

    #[test]
    fn an_idle_chips_popover_borrows_the_open_window_rather_than_widening_the_idle_one() {
        // A chip can open a popover while the panel is closed. The room comes from
        // putting the window at its open size, never from fattening the idle window,
        // which has to stay snug or it swallows clicks meant for the desktop.
        let g = geometry(ScreenEdge::Trailing, 0.5);
        assert!(g.window_frame(false).width < popover_offset());
        assert!(g.window_frame(true).width >= popover_offset() + g.popover_width);
    }

    #[test]
    fn a_strip_still_hugs_its_edge_with_the_popover_room_inward() {
        // The reserve must grow the window inward, never push the strip off the bezel.
        for edge in [ScreenEdge::Trailing, ScreenEdge::Leading, ScreenEdge::Top, ScreenEdge::Bottom] {
            let m = geometry(edge, 0.5).metrics_in(true, true);
            let flush = match edge {
                ScreenEdge::Trailing => (m.offset_x + m.shape_width - m.window_width).abs(),
                ScreenEdge::Leading => m.offset_x.abs(),
                ScreenEdge::Top => m.offset_y.abs(),
                ScreenEdge::Bottom => (m.offset_y + m.shape_height - m.window_height).abs(),
            };
            assert!(flush < 0.001, "{edge:?} is not flush: {flush}");
        }
    }

    #[test]
    fn a_strip_never_hangs_off_the_ends_of_its_edge() {
        for alignment in [0.0, 0.5, 1.0] {
            let s = settings(ScreenEdge::Trailing, alignment);
            let frame = PanelGeometry::new(&s, screen(), s.enabled_slot_count()).window_frame(true);
            assert!(frame.y >= screen().y - 0.001, "alignment {alignment}");
            assert!(frame.max_y() <= screen().max_y() + 0.001, "alignment {alignment}");
        }
    }

    #[test]
    fn the_settings_row_leads_the_strip_and_every_enabled_widget_follows() {
        for edge in [ScreenEdge::Trailing, ScreenEdge::Top] {
            let s = settings(edge, 0.5);
            let spans = row_spans(&s);
            assert_eq!(spans.len(), s.enabled_slot_count() + 1);
            assert_eq!(spans[0].row, StripRow::Settings);
            assert_eq!(spans[1].row, StripRow::Widget("clock".into()));
            // Every Row is reachable at its own centre.
            for span in &spans {
                assert_eq!(row_at(&spans, span.start + span.length / 2.0), Some(&span.row));
            }
            // The Strip is long enough to hold them all, flares included.
            let horizontal = edge.grows_horizontally();
            let last = spans.last().unwrap();
            let drawn = StripLayout::resolve(&s).extent + 2.0 * strip_inverse_radius(horizontal);
            assert!(drawn >= last.start + last.length + CHIP_END_PADDING, "{edge:?}");
            // And the first Row starts clear of the flare rather than under it.
            assert!(spans[0].start >= strip_inverse_radius(horizontal), "{edge:?}");
        }
    }

    #[test]
    fn a_disabled_widget_leaves_no_row_behind_it() {
        let mut s = settings(ScreenEdge::Trailing, 0.5);
        s.slots[1].is_enabled = false;
        let spans = row_spans(&s);
        assert!(!spans.iter().any(|span| span.row == StripRow::Widget("media".into())));
        // And the Strip shrinks with it, rather than leaving a gap where it was.
        let full = settings(ScreenEdge::Trailing, 0.5);
        assert!(StripLayout::resolve(&s).extent < StripLayout::resolve(&full).extent);
    }

    #[test]
    fn the_gaps_between_rows_belong_to_no_row() {
        // Sliding down the Strip must not flash a popover for every widget on the way.
        let s = settings(ScreenEdge::Trailing, 0.5);
        let spans = row_spans(&s);
        let between = spans[0].start + spans[0].length + CHIP_SPACING / 2.0;
        assert_eq!(row_at(&spans, between), None);
    }
}

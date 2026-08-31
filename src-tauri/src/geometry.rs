//! Turns settings plus a display into concrete window frames.
//!
//! Ported from the Swift implementation, with one simplification: Tauri reports monitor
//! coordinates with the origin at the top left, where Cocoa used the bottom left. That
//! removes the axis flip the Swift version needed, so alignment reads the same way on
//! every edge — 0 is always top or left.

use crate::settings::{ScreenEdge, Settings};
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
    pub fn contains(&self, x: f64, y: f64) -> bool {
        x >= self.x && x < self.max_x() && y >= self.y && y < self.max_y()
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
}

pub const CHIP_SPACING: f64 = 5.0;
pub const CHIP_END_PADDING: f64 = 9.0;
/// Room reserved around the open panel for its drop shadow.
pub const SHADOW_MARGIN: f64 = 34.0;
/// Slack around the idle handle so the pointer doesn't need pixel precision.
pub const HOVER_BUFFER: f64 = 22.0;

impl HandleLayout {
    pub fn resolve(settings: &Settings, widget_count: usize) -> Self {
        if settings.handle_chips.is_empty() {
            return Self {
                depth: settings.handle_thickness.max(2.0),
                extent: settings.handle_length.max(12.0),
                shows_content: false,
            };
        }
        let horizontal = settings.edge.grows_horizontally();
        let content: f64 = settings
            .handle_chips
            .iter()
            .map(|chip| chip.extent(horizontal, widget_count))
            .sum();
        let gaps = CHIP_SPACING * settings.handle_chips.len().saturating_sub(1) as f64;
        Self {
            depth: settings.handle_content_thickness.max(18.0),
            extent: (content + gaps + CHIP_END_PADDING * 2.0).max(28.0),
            shows_content: true,
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
}

pub struct PanelGeometry {
    pub edge: ScreenEdge,
    pub screen: Rect,
    pub alignment: f64,
    pub body_depth: f64,
    pub body_extent: f64,
    pub handle: HandleLayout,
    pub corner_radius: f64,
    pub edge_inset: f64,
}

impl PanelGeometry {
    pub fn new(settings: &Settings, screen: Rect, widget_count: usize) -> Self {
        // On the top and bottom edges the "width" setting means the extent along the
        // edge, so the user never has to re-tune both sliders after re-docking.
        let (body_depth, body_extent) = if settings.edge.grows_horizontally() {
            (settings.panel_width, settings.panel_height)
        } else {
            (settings.panel_height, settings.panel_width)
        };
        Self {
            edge: settings.edge,
            screen,
            alignment: settings.alignment,
            body_depth,
            body_extent,
            handle: HandleLayout::resolve(settings, widget_count),
            corner_radius: settings.corner_radius,
            edge_inset: settings.edge_inset,
        }
    }

    pub fn expanded_inverse_radius(&self) -> f64 {
        (self.corner_radius * 0.6).min(14.0)
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

    fn depth(&self, expanded: bool) -> f64 {
        if expanded { self.body_depth } else { self.handle.depth }
    }

    fn extent(&self, expanded: bool) -> f64 {
        if expanded { self.body_extent } else { self.handle.extent }
    }

    fn inverse_radius(&self, expanded: bool) -> f64 {
        if expanded { self.expanded_inverse_radius() } else { self.handle_inverse_radius() }
    }

    fn margin(&self, expanded: bool) -> f64 {
        if expanded { SHADOW_MARGIN } else { HOVER_BUFFER }
    }

    /// Centre of the panel along its edge, in display coordinates.
    pub fn edge_center(&self, expanded: bool) -> f64 {
        let half = self.extent(expanded) / 2.0 + self.inverse_radius(expanded) + self.margin(expanded);
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
        let depth = self.depth(expanded) + margin;
        let extent = self.extent(expanded) + 2.0 * self.inverse_radius(expanded) + 2.0 * margin;
        let center = self.edge_center(expanded);

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

    /// What the frontend draws, in window-local coordinates.
    pub fn metrics(&self, expanded: bool) -> PanelMetrics {
        let margin = self.margin(expanded);
        let inverse = self.inverse_radius(expanded);
        let depth = self.depth(expanded);
        let extent = self.extent(expanded) + 2.0 * inverse;

        let (shape_width, shape_height) = if self.edge.grows_horizontally() {
            (depth, extent)
        } else {
            (extent, depth)
        };
        // The shape hugs the docked edge; the margin sits on the inward side.
        let (offset_x, offset_y) = match self.edge {
            ScreenEdge::Trailing => (margin, margin),
            ScreenEdge::Leading => (0.0, margin),
            ScreenEdge::Top => (margin, 0.0),
            ScreenEdge::Bottom => (margin, margin),
        };

        PanelMetrics {
            expanded,
            shape_width,
            shape_height,
            corner_radius: if expanded { self.corner_radius } else { self.handle_corner_radius() },
            inverse_radius: inverse,
            shows_content: expanded || self.handle.shows_content,
            offset_x,
            offset_y,
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
            panel_width: 372.0,
            panel_height: 540.0,
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
            geometry(ScreenEdge::Trailing, 0.0).edge_center(true)
                < geometry(ScreenEdge::Trailing, 1.0).edge_center(true)
        );
        assert!(
            geometry(ScreenEdge::Top, 0.0).edge_center(true)
                < geometry(ScreenEdge::Top, 1.0).edge_center(true)
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
    fn width_and_height_swap_roles_on_the_top_and_bottom_edges() {
        let side = geometry(ScreenEdge::Trailing, 0.5);
        let top = geometry(ScreenEdge::Top, 0.5);
        assert_eq!((side.body_depth, side.body_extent), (372.0, 540.0));
        assert_eq!((top.body_depth, top.body_extent), (540.0, 372.0));
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
        assert_eq!(one.depth, 30.0);

        s.handle_chips = vec![IdleChip::Clock, IdleChip::NowPlaying];
        assert!(HandleLayout::resolve(&s, 5).extent > one.extent);
    }

    #[test]
    fn handle_extent_accounts_for_spacing_between_chips() {
        let mut s = settings(ScreenEdge::Trailing, 0.5);
        s.handle_chips = vec![IdleChip::Clock, IdleChip::Cpu, IdleChip::Battery];
        let content: f64 = s.handle_chips.iter().map(|c| c.extent(true, 5)).sum();
        let expected = content + CHIP_SPACING * 2.0 + CHIP_END_PADDING * 2.0;
        assert!((HandleLayout::resolve(&s, 5).extent - expected).abs() < 0.001);
    }

    #[test]
    fn metrics_reserve_the_shadow_margin_on_the_inward_side_only() {
        let g = geometry(ScreenEdge::Trailing, 0.5);
        let open = g.metrics(true);
        let frame = g.window_frame(true);
        // Shape plus its offset must exactly fill the window on the docked axis.
        assert!((open.offset_x + open.shape_width - frame.width).abs() < 0.001);
    }
}

//! Persisted configuration.
//!
//! Every field carries a `serde` default, so a settings file written by an older build
//! — one predating a field added since — still loads and the new field simply arrives
//! at its default. In the Swift version this needed a hand-written decoder; here it is
//! one attribute.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ScreenEdge {
    Top,
    Bottom,
    Leading,
    Trailing,
}

impl ScreenEdge {
    /// True for the left and right edges, where the panel extends horizontally into the
    /// display. This describes the panel's growth direction, not the orientation of the
    /// edge itself.
    pub fn grows_horizontally(self) -> bool {
        matches!(self, ScreenEdge::Leading | ScreenEdge::Trailing)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ActivationMode {
    Hover,
    Click,
    HotkeyOnly,
}

/// One reading the handle shows while the panel is closed.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum IdleChip {
    Clock,
    Date,
    Cpu,
    Memory,
    Battery,
    NowPlaying,
    Clipboard,
    WidgetIcons,
}

impl IdleChip {
    /// True when the chip's value has to be sampled while the panel is closed.
    pub fn needs_metrics(self) -> bool {
        matches!(self, IdleChip::Cpu | IdleChip::Memory | IdleChip::Battery)
    }

    pub fn needs_media(self) -> bool {
        matches!(self, IdleChip::NowPlaying)
    }

    /// Room this chip needs along the edge, reserved whether or not it currently has a
    /// value so the handle never resizes underneath the pointer.
    ///
    /// True for the readings that draw an arc rather than a bare number: the ones whose
    /// value is a fraction of a known whole, and so has somewhere to travel.
    pub fn draws_arc(self) -> bool {
        matches!(self, IdleChip::Cpu | IdleChip::Memory | IdleChip::Battery)
    }

    /// `grows_horizontally` is true on the left and right edges, where chips stack in a
    /// column — so it asks for the chip's height. On the top and bottom they sit side
    /// by side and it asks for the width, which is larger for anything rendering text
    /// on one line.
    ///
    /// `ring` is `ring_diameter` for the handle in question: an arc chip is sized around
    /// the circle it draws, so a handle the user has made thinner produces smaller
    /// chips rather than overflowing ones.
    pub fn extent(self, grows_horizontally: bool, widget_count: usize, ring: f64) -> f64 {
        if matches!(self, IdleChip::WidgetIcons) {
            let each: f64 = if grows_horizontally { 19.0 } else { 21.0 };
            return each.max(each * widget_count as f64);
        }
        if self.draws_arc() {
            // Stacked, the number sits under the ring; side by side, beside it.
            return if grows_horizontally { ring + 15.0 } else { ring + 30.0 };
        }
        if grows_horizontally {
            match self {
                IdleChip::Clock | IdleChip::Date => 30.0,
                IdleChip::NowPlaying | IdleChip::Clipboard => 24.0,
                _ => 24.0,
            }
        } else {
            match self {
                IdleChip::Clock => 40.0,
                IdleChip::Date => 44.0,
                IdleChip::NowPlaying => 26.0,
                IdleChip::Clipboard => 32.0,
                _ => 32.0,
            }
        }
    }
}

/// Diameter of the arc a reading draws in the idle handle.
///
/// Derived from the handle's thickness rather than fixed, so a handle someone has
/// already sized keeps working: the ring shrinks to fit instead of overflowing. The
/// floor is where a stroke and an icon stop being distinguishable; the ceiling is where
/// a bigger ring stops reading as a chip and starts reading as a dial.
pub fn ring_diameter(content_thickness: f64) -> f64 {
    (content_thickness - 6.0).clamp(18.0, 38.0)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum WidgetKind {
    BuiltIn,
    Web,
}

/// One entry in the user's panel: which widget, in what order, and its preferences.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WidgetSlot {
    pub id: String,
    pub kind: WidgetKind,
    pub widget_id: String,
    #[serde(default = "default_true")]
    pub is_enabled: bool,
    #[serde(default)]
    pub preferences: serde_json::Map<String, serde_json::Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Hotkey {
    pub accelerator: String,
    pub is_enabled: bool,
}

fn default_true() -> bool {
    true
}

macro_rules! defaulted {
    ($name:ident, $ty:ty, $value:expr) => {
        fn $name() -> $ty {
            $value
        }
    };
}

defaulted!(d_edge, ScreenEdge, ScreenEdge::Trailing);
defaulted!(d_alignment, f64, 0.42);
defaulted!(d_popover_width, f64, 236.0);
defaulted!(d_popover_height, f64, 320.0);
defaulted!(d_handle_thickness, f64, 5.0);
defaulted!(d_handle_length, f64, 108.0);
defaulted!(d_handle_content_thickness, f64, 44.0);
defaulted!(d_activation, ActivationMode, ActivationMode::Hover);
defaulted!(d_open_delay, f64, 0.14);
defaulted!(d_close_delay, f64, 0.42);
defaulted!(d_opacity, f64, 0.96);
defaulted!(d_accent, String, "#6E9BFF".into());
defaulted!(d_clipboard_limit, usize, 120);

fn d_handle_chips() -> Vec<IdleChip> {
    // The clock alone: it shows the feature, samples nothing, and prompts for nothing.
    vec![IdleChip::Clock]
}

fn d_hotkey() -> Hotkey {
    Hotkey {
        // CmdOrControl resolves to Command on macOS and Control on Windows; a bare
        // "Cmd" would fail to register on Windows.
        accelerator: "CmdOrControl+Alt+N".into(),
        is_enabled: true,
    }
}

fn d_slots() -> Vec<WidgetSlot> {
    ["clock", "media", "system", "launcher", "clipboard"]
        .iter()
        .map(|id| WidgetSlot {
            id: format!("builtin-{id}"),
            kind: WidgetKind::BuiltIn,
            widget_id: (*id).into(),
            is_enabled: true,
            preferences: Default::default(),
        })
        .collect()
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Settings {
    pub edge: ScreenEdge,
    /// Where the panel sits along its edge: 0 is top/left, 1 is bottom/right.
    pub alignment: f64,
    /// The Popover's own size. There is no other surface left to size: the Strip is
    /// measured from its rows, so these are the only dimensions a user can set.
    pub popover_width: f64,
    pub popover_height: f64,
    pub handle_thickness: f64,
    pub handle_length: f64,
    pub handle_chips: Vec<IdleChip>,
    pub handle_content_thickness: f64,
    pub edge_inset: f64,

    pub activation: ActivationMode,
    pub open_delay: f64,
    pub close_delay: f64,
    pub close_on_outside_click: bool,

    pub opacity: f64,
    pub accent_hex: String,
    pub shows_handle_when_idle: bool,
    pub reduce_motion: bool,

    pub launch_at_login: bool,
    pub hotkey: Hotkey,
    pub preferred_screen: Option<String>,

    pub slots: Vec<WidgetSlot>,
    pub shell_approved_widgets: Vec<String>,
    pub network_approved_widgets: Vec<String>,
    pub clipboard_approved_widgets: Vec<String>,

    pub clipboard_history_limit: usize,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            edge: d_edge(),
            alignment: d_alignment(),
            popover_width: d_popover_width(),
            popover_height: d_popover_height(),
            handle_thickness: d_handle_thickness(),
            handle_length: d_handle_length(),
            handle_chips: d_handle_chips(),
            handle_content_thickness: d_handle_content_thickness(),
            edge_inset: 0.0,
            activation: d_activation(),
            open_delay: d_open_delay(),
            close_delay: d_close_delay(),
            close_on_outside_click: true,
            opacity: d_opacity(),
            accent_hex: d_accent(),
            shows_handle_when_idle: true,
            reduce_motion: false,
            launch_at_login: false,
            hotkey: d_hotkey(),
            preferred_screen: None,
            slots: d_slots(),
            shell_approved_widgets: Vec::new(),
            network_approved_widgets: Vec::new(),
            clipboard_approved_widgets: Vec::new(),
            clipboard_history_limit: d_clipboard_limit(),
        }
    }
}

/// Where settings, widgets and clipboard history live.
///
/// Deliberately *not* the Swift build's `Notchly` directory. The two write
/// incompatible slot records (`widgetID` versus `widgetId`), so a shared settings file
/// means each silently resets the other's widget list — and anyone upgrading from the
/// Swift app still has one on disk. Renaming would strand every existing install.
pub fn support_dir() -> PathBuf {
    let base = dirs_next_config().unwrap_or_else(std::env::temp_dir);
    let dir = base.join("Notchly (Tauri)");
    let _ = std::fs::create_dir_all(&dir);
    dir
}

fn dirs_next_config() -> Option<PathBuf> {
    #[cfg(target_os = "macos")]
    {
        std::env::var_os("HOME").map(|home| PathBuf::from(home).join("Library/Application Support"))
    }
    #[cfg(target_os = "windows")]
    {
        std::env::var_os("APPDATA").map(PathBuf::from)
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".config"))
    }
}

pub fn widgets_dir() -> PathBuf {
    let dir = support_dir().join("Widgets");
    let _ = std::fs::create_dir_all(&dir);
    dir
}

pub fn settings_path() -> PathBuf {
    support_dir().join("settings.json")
}

impl Settings {
    pub fn load() -> Self {
        std::fs::read_to_string(settings_path())
            .ok()
            .and_then(|text| serde_json::from_str(&text).ok())
            .unwrap_or_default()
    }

    pub fn save(&self) {
        if let Ok(text) = serde_json::to_string_pretty(self) {
            let _ = std::fs::write(settings_path(), text);
        }
    }

    pub fn enabled_slot_count(&self) -> usize {
        self.slots.iter().filter(|slot| slot.is_enabled).count()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn settings_file_from_an_older_version_still_loads() {
        // Every field has a default, so a file predating a field must not reset the
        // user's whole configuration.
        // "panelWidth" is a field this build no longer has: an unknown key must be
        // ignored rather than failing the whole decode.
        let json = r#"{ "edge": "leading", "popoverWidth": 300, "panelWidth": 372 }"#;
        let settings: Settings = serde_json::from_str(json).unwrap();
        assert_eq!(settings.edge, ScreenEdge::Leading);
        assert_eq!(settings.popover_width, 300.0);
        assert_eq!(settings.slots.len(), 5);
        assert_eq!(settings.activation, ActivationMode::Hover);
    }

    #[test]
    fn defaults_round_trip_through_json() {
        let settings = Settings::default();
        let text = serde_json::to_string(&settings).unwrap();
        assert_eq!(serde_json::from_str::<Settings>(&text).unwrap(), settings);
    }

    #[test]
    fn default_handle_costs_nothing_to_display() {
        // The clock samples nothing and prompts for nothing; anything that polls is opt-in.
        let settings = Settings::default();
        assert!(!settings.handle_chips.iter().any(|chip| chip.needs_metrics()));
        assert!(!settings.handle_chips.iter().any(|chip| chip.needs_media()));
    }

    #[test]
    fn only_system_backed_chips_request_sampling() {
        use IdleChip::*;
        for chip in [Cpu, Memory, Battery] {
            assert!(chip.needs_metrics(), "{chip:?}");
        }
        for chip in [Clock, Date, Clipboard, WidgetIcons] {
            assert!(!chip.needs_metrics(), "{chip:?}");
            assert!(!chip.needs_media(), "{chip:?}");
        }
        assert!(NowPlaying.needs_media());
    }

    #[test]
    fn stacked_chips_need_less_room_than_ones_on_a_single_line() {
        assert!(IdleChip::Clock.extent(true, 0, 34.0) < IdleChip::Clock.extent(false, 0, 34.0));
    }

    #[test]
    fn widget_icons_chip_scales_with_the_number_of_widgets() {
        assert!(IdleChip::WidgetIcons.extent(true, 2, 34.0) < IdleChip::WidgetIcons.extent(true, 6, 34.0));
        // An empty panel still draws a placeholder glyph.
        assert!(IdleChip::WidgetIcons.extent(true, 0, 34.0) > 0.0);
    }
}

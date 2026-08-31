//! Descriptors for the compiled-in widgets.
//!
//! Custom widgets describe themselves in `widget.json`; the built-ins describe
//! themselves here in the same shape. Every piece of settings UI consumes descriptors,
//! so a folder the user drops in gets exactly the same native controls as Now Playing —
//! there is no custom-widget-only code path.

use crate::widgets::SettingField;
use serde::Serialize;
use serde_json::json;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Descriptor {
    pub id: &'static str,
    pub name: &'static str,
    pub summary: &'static str,
    pub settings: Vec<SettingField>,
}

fn field(
    key: &str,
    label: &str,
    kind: &str,
    default: serde_json::Value,
    help: Option<&str>,
    options: Option<Vec<&str>>,
    range: Option<(f64, f64)>,
) -> SettingField {
    SettingField {
        key: key.into(),
        label: label.into(),
        kind: kind.into(),
        help: help.map(str::to_string),
        default_value: Some(default),
        options: options.map(|list| list.into_iter().map(str::to_string).collect()),
        minimum: range.map(|(min, _)| min),
        maximum: range.map(|(_, max)| max),
    }
}

pub fn all() -> Vec<Descriptor> {
    vec![
        Descriptor {
            id: "clock",
            name: "Clock",
            summary: "Time, date and week number.",
            settings: vec![
                field("format", "Time format", "select", json!("24-hour"), None,
                      Some(vec!["24-hour", "12-hour"]), None),
                field("showSeconds", "Show seconds", "boolean", json!(false), None, None, None),
            ],
        },
        Descriptor {
            id: "media",
            name: "Now Playing",
            summary: "Transport for Music and Spotify.",
            settings: vec![],
        },
        Descriptor {
            id: "system",
            name: "System",
            summary: "CPU, memory, disk, network and battery.",
            settings: vec![
                field("showDisk", "Show disk", "boolean", json!(true), None, None, None),
                field("showNetwork", "Show network", "boolean", json!(true), None, None, None),
                field("showBattery", "Show battery", "boolean", json!(true), None, None, None),
                field("showProcesses", "Show top processes", "boolean", json!(true),
                      Some("Samples the process list while the panel is open."), None, None),
            ],
        },
        Descriptor {
            id: "launcher",
            name: "Quick Launcher",
            summary: "Search and launch installed apps.",
            settings: vec![],
        },
        Descriptor {
            id: "clipboard",
            name: "Clipboard",
            summary: "Everything you have copied, searchable.",
            settings: vec![
                field("visibleCount", "Entries shown", "number", json!(6), None, None, Some((3.0, 15.0))),
            ],
        },
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_builtin_has_an_id_name_and_summary() {
        for descriptor in all() {
            assert!(!descriptor.id.is_empty());
            assert!(!descriptor.name.is_empty());
            assert!(!descriptor.summary.is_empty());
        }
    }

    #[test]
    fn default_slots_all_name_a_real_builtin() {
        let ids: Vec<&str> = all().iter().map(|d| d.id).collect();
        for slot in crate::settings::Settings::default().slots {
            assert!(ids.contains(&slot.widget_id.as_str()), "{} has no descriptor", slot.widget_id);
        }
    }

    #[test]
    fn every_schema_default_matches_its_declared_type() {
        for descriptor in all() {
            for field in descriptor.settings {
                let value = field.default_value.expect("a default");
                match field.kind.as_str() {
                    "boolean" => assert!(value.is_boolean(), "{}", field.key),
                    "number" => assert!(value.is_number(), "{}", field.key),
                    _ => assert!(value.is_string(), "{}", field.key),
                }
                if field.kind == "select" {
                    let options = field.options.expect("options");
                    assert!(options.contains(&value.as_str().unwrap().to_string()),
                            "{} default is not one of its options", field.key);
                }
            }
        }
    }
}

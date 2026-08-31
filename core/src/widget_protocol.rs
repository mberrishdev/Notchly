//! Serves widget files over the `widget://` scheme.
//!
//! Two things happen here that a plain static file server wouldn't do:
//!
//! 1. The entry HTML gets the Notchly runtime and base stylesheet injected, which is
//!    how `window.notchly` reaches a page the author never asked to instrument.
//! 2. Every response carries a Content-Security-Policy built from the widget's granted
//!    permissions. That is the replacement for `WKContentRuleList`: a widget without
//!    network access cannot reach the network even by loading a remote script.

use crate::widgets::Permission;
use std::path::{Component, Path, PathBuf};

pub const RUNTIME_JS: &str = include_str!("../../ui/lib/widget-runtime.js");
pub const BASE_CSS: &str = include_str!("../../ui/styles/widget-base.css");

/// Splits `widget://localhost/<widget-id>/<path>` into its two halves.
///
/// The first segment is the widget's *manifest id*, not its folder name — the folder is
/// looked up from the catalog, so a widget is addressed by the identity it declares.
pub fn split_request(request_path: &str) -> Option<(String, String)> {
    let trimmed = request_path.trim_start_matches('/');
    let (widget_id, rest) = trimmed.split_once('/').unwrap_or((trimmed, ""));
    if widget_id.is_empty() {
        return None;
    }
    Some((widget_id.to_string(), rest.to_string()))
}

/// Joins a relative request path onto a widget's folder.
///
/// Returns `None` for anything that could climb out of that folder, so a widget cannot
/// read `../../../etc/passwd` by asking nicely.
pub fn safe_join(folder: &Path, relative: &str) -> Option<PathBuf> {
    let mut file = folder.to_path_buf();
    for component in Path::new(relative).components() {
        match component {
            Component::Normal(part) => file.push(part),
            Component::CurDir => {}
            _ => return None,
        }
    }
    Some(file)
}

pub fn content_type(path: &Path) -> &'static str {
    match path.extension().and_then(|ext| ext.to_str()) {
        Some("html") | Some("htm") => "text/html; charset=utf-8",
        Some("js") | Some("mjs") => "text/javascript; charset=utf-8",
        Some("css") => "text/css; charset=utf-8",
        Some("json") => "application/json; charset=utf-8",
        Some("svg") => "image/svg+xml",
        Some("png") => "image/png",
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("webp") => "image/webp",
        Some("woff2") => "font/woff2",
        Some("woff") => "font/woff",
        _ => "application/octet-stream",
    }
}

/// The policy a widget runs under. Widgets are offline until granted, and that is
/// enforced here rather than by asking politely.
pub fn csp(granted: &[Permission]) -> String {
    let network = granted.contains(&Permission::Network);
    let remote = if network { " https:" } else { "" };
    let connect = if network { "https:" } else { "'none'" };
    format!(
        "default-src 'none'; \
         script-src widget: 'unsafe-inline'{remote}; \
         style-src widget: 'unsafe-inline'{remote}; \
         img-src widget: data: blob:{remote}; \
         font-src widget: data:{remote}; \
         media-src widget: data: blob:{remote}; \
         connect-src {connect}; \
         frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
    )
}

/// Injects the runtime and base stylesheet as the first things in the document, so a
/// widget's own styles and scripts still win.
pub fn inject(html: &str, widget_id: &str, settings_json: &str, theme_json: &str) -> String {
    let preamble = format!(
        "<style data-notchly=\"base\">{BASE_CSS}</style>\
         <script data-notchly=\"runtime\">\
         window.__NOTCHLY_WIDGET__ = {{ id: {id}, settings: {settings_json}, theme: {theme_json} }};\
         {RUNTIME_JS}\
         </script>",
        id = serde_json::to_string(widget_id).unwrap_or_else(|_| "\"\"".into()),
    );

    let lower = html.to_lowercase();
    if let Some(index) = lower.find("<head>") {
        let at = index + "<head>".len();
        return format!("{}{}{}", &html[..at], preamble, &html[at..]);
    }
    if let Some(index) = lower.find("<html") {
        if let Some(close) = html[index..].find('>') {
            let at = index + close + 1;
            return format!("{}{}{}", &html[..at], preamble, &html[at..]);
        }
    }
    format!("{preamble}{html}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_a_request_into_widget_id_and_path() {
        assert_eq!(
            split_request("/com.you.thing/index.html"),
            Some(("com.you.thing".into(), "index.html".into()))
        );
        assert_eq!(
            split_request("/w/assets/app.js"),
            Some(("w".into(), "assets/app.js".into()))
        );
    }

    #[test]
    fn refuses_an_empty_widget_id() {
        assert!(split_request("/").is_none());
        assert!(split_request("").is_none());
    }

    #[test]
    fn joins_paths_inside_the_widget_folder() {
        let folder = Path::new("/widgets/thing");
        assert_eq!(
            safe_join(folder, "assets/app.js"),
            Some(PathBuf::from("/widgets/thing/assets/app.js"))
        );
        assert_eq!(safe_join(folder, "./index.html"), Some(PathBuf::from("/widgets/thing/index.html")));
    }

    #[test]
    fn refuses_paths_that_climb_out_of_the_widget_folder() {
        let folder = Path::new("/widgets/thing");
        assert!(safe_join(folder, "../other/index.html").is_none());
        assert!(safe_join(folder, "../../etc/passwd").is_none());
        assert!(safe_join(folder, "/etc/passwd").is_none());
    }

    #[test]
    fn every_joined_path_stays_under_the_widget_folder() {
        let folder = Path::new("/widgets/thing");
        for request in ["index.html", "a/b/c.png", "./style.css"] {
            let path = safe_join(folder, request).unwrap();
            assert!(path.starts_with(folder), "{request} escaped to {path:?}");
        }
    }

    #[test]
    fn a_widget_without_network_permission_cannot_connect() {
        let policy = csp(&[Permission::System]);
        assert!(policy.contains("connect-src 'none'"));
        assert!(!policy.contains("https:"));
    }

    #[test]
    fn granting_network_opens_https_only() {
        let policy = csp(&[Permission::Network]);
        assert!(policy.contains("connect-src https:"));
        assert!(!policy.contains("http://"));
    }

    #[test]
    fn every_policy_blocks_nested_frames_and_form_posts() {
        for granted in [vec![], vec![Permission::Network]] {
            let policy = csp(&granted);
            assert!(policy.contains("frame-src 'none'"));
            assert!(policy.contains("form-action 'none'"));
            assert!(policy.contains("object-src 'none'"));
        }
    }

    #[test]
    fn runtime_is_injected_immediately_after_head() {
        let html = "<html><head><title>x</title></head><body></body></html>";
        let out = inject(html, "a.b", "{}", "{}");
        let head = out.find("<head>").unwrap();
        let runtime = out.find("data-notchly=\"runtime\"").unwrap();
        let title = out.find("<title>").unwrap();
        // Before the author's own markup, so their styles and scripts still win.
        assert!(head < runtime && runtime < title);
    }

    #[test]
    fn injection_copes_with_documents_that_have_no_head() {
        assert!(inject("<html><body>hi</body></html>", "a", "{}", "{}").contains("data-notchly"));
        assert!(inject("just text", "a", "{}", "{}").contains("data-notchly"));
    }

    #[test]
    fn content_types_cover_what_a_widget_actually_ships() {
        assert_eq!(content_type(Path::new("a/index.html")), "text/html; charset=utf-8");
        assert_eq!(content_type(Path::new("a/app.js")), "text/javascript; charset=utf-8");
        assert_eq!(content_type(Path::new("a/logo.png")), "image/png");
        assert_eq!(content_type(Path::new("a/unknown.xyz")), "application/octet-stream");
    }
}

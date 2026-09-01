# Notchly

A notch-shaped panel that docks to any edge of the display, holds widgets, and lets
anyone drop in their own as a plain HTML/CSS/JS folder. Read `CONTEXT.md` first — it is
the domain model and rulebook; its terminology is binding.

Built with Tauri: a Rust core that owns the window and everything touching the system,
and a plain HTML/CSS/JS frontend that draws the panel. `CONTEXT.md` is the single source
of truth for the domain model and terminology.

## State of the repo

Working end to end on macOS, with Windows builds produced by CI: the panel opens on hover, docks to all four edges, drags
to reposition, shows a configurable ambient strip while closed, hosts five built-in
widgets plus any number of custom ones with hot reload, and has a five-pane settings
window. Windows runtime behavior still needs validation on Windows hardware.

76 Rust tests cover the notch geometry, window frames, drag placement, idle handle
sizing, settings decoding, permission gating, the widget manifest format, the widget
protocol's path handling and content policy, the bridge's HTTP surface, and launcher
search ranking. They are the parts where a silent mistake would be invisible on screen;
the views are not tested.

## Stack decisions (already made, do not relitigate)

- **Rust owns the window and the arithmetic; the frontend draws what it is told.** The
  `panel-state` event carries shape size, radii and offsets, so there is one source of
  truth for geometry rather than two implementations that drift
- **No bundler and no framework.** `frontendDist` points straight at `ui/`. The panel
  is the same kind of thing the widgets are — HTML in a webview — and a build step
  would only obscure that
- **Custom widgets are iframes, not one webview each.** Tauri's multi-webview support
  is behind an `unstable` flag with open bugs. Sandboxed without `allow-same-origin`,
  so each widget gets an opaque origin
- **Hover is decided in Rust, not the DOM.** A non-activating panel does not reliably
  deliver `mouseenter`/`mouseleave`, and the window resizes underneath the pointer as
  it opens
- **The panel is opaque.** A shaped window cannot sit on a real backdrop blur without
  it showing as a rectangle behind the concave corners, and a translucent fill with
  nothing behind it reads as a rendering fault

## Layout

Two top-level source trees, because there are two programs: a Rust binary that owns the
window, and a web page that draws inside it. Named `core` and `ui` rather than Tauri's
default `src-tauri` and a bare `src`, which read as a duplicate rather than a split.
The Tauri CLI locates `tauri.conf.json` by searching, so the directory name is free.

- `ui/` — the frontend, running inside the webview. `main.js` is the state machine;
  `lib/notch-shape.js` builds the outline; `lib/panel-view.js` paints and animates it;
  `lib/widget-host.js` hosts custom widgets and relays their bridge calls;
  `lib/widget-runtime.js` is injected into them; `settings.js` and
  `lib/settings-*.js` are the settings window
- `core/src/` — the Rust binary
  - `panel.rs` — the window and the open/close state machine
  - `geometry.rs` — settings + display → window frames, and `IdleHandleLayout`
  - `hover.rs` — the cursor watchdog behind hover-to-open
  - `settings.rs` — the persisted model, with serde defaults for tolerant decoding
  - `widgets.rs`, `widget_protocol.rs`, `bridge.rs` — discovery, the `widget://`
    scheme with its per-widget CSP, and the `window.notchly` implementation
  - `secrets.rs` — widget credentials in the OS store, so a `secret` setting never
    reaches `settings.json`
  - `services/` — everything that talks to the system: metrics, media, clipboard,
    apps, notifications, and the sampling cadence in `ambient.rs`
  - `platform.rs` — per-platform native window behaviour
- `core/resources/ExampleWidgets/` — bundled starter widgets, copied into the
  user's widgets folder on first launch
- `scripts/` — icon generators. They are Swift, and macOS-only, because they draw with
  AppKit; they are developer tools run by hand, not part of the build, so nothing about
  shipping on Windows depends on them

## Code style

- 4-space indentation in Rust, 2 in the frontend (see `.editorconfig`)
- No section-marker comments — a file that needs them needs splitting
- Comments explain why, not what, and are worth writing where a reader would otherwise
  assume a mistake

## Testing

```bash
cd core && cargo test          # 76 tests, headless
npx tauri build --bundles app       # release bundle
```

Pure logic the UI depends on is pulled into a testable type rather than tested through
a view — `Placement`, `HandleLayout` and `apps::rank` all exist in that shape.

Setting `NOTCHLY_CAPTURE_DIR` makes the app walk itself through its states and save a
PNG of each. It sits behind the `capture` Cargo feature — `cargo run --features
capture` — so the harness never ships in a release build. It only works while the
window server is compositing the panel: launched straight from the binary the app is
never activated, WebKit reports the document hidden, and every capture comes back
transparent even though the DOM is correct. **A blank capture means "not composited",
not "not rendered."**

## Roadmap

1. ~~Panel shell: geometry, window, open/close state machine, four-edge docking~~ done
2. ~~System metrics, menu bar item, global hotkey, launch at login~~ done
3. ~~Custom widget host: `widget://` scheme, per-widget CSP, permissions, hot reload~~ done
4. ~~Five built-in widgets~~ done
5. ~~Settings window~~ done
6. ~~Windows: `WS_EX_NOACTIVATE`, and Now Playing via
   `GlobalSystemMediaTransportControlsSessionManager`~~ written, unvalidated on
   Windows hardware
7. Launcher app icons; per-widget file isolation — not started

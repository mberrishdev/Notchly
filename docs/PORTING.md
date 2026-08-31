# Porting Notchly to Tauri

Status of the `tauri` branch: what works, what changed shape, and what is still
missing. The Swift app on `main` remains the reference implementation — both are in
the tree so they can be run side by side and diffed for behaviour.

## Why a rewrite and not a port

Nothing compiles across. Of the Swift app's 7,654 lines, 78 of 85 files import
AppKit, SwiftUI, WebKit, IOKit, Carbon or Combine — none of which exist on Windows.
Six percent of the code was portable, and the largest portable file was JavaScript in
a Swift string.

The valuable asset was never the Swift. It was the widget contract: `widget.json`
plus the `window.notchly` API. Those carried over verbatim, and the three bundled
example widgets run byte-for-byte unchanged.

## The risk that decided the approach

Tauri's transparent windows are widely reported to work under `tauri dev` and render
opaque in a bundled release `.app`. Notchly is nothing without a transparent, shaped
window, so that was validated before anything else was built.

The app captures its own window — no Screen Recording permission is needed for your
own windows — and reads back the alpha channel. Across a release bundle, left to
right:

```
0, 12, 88, 250, 250, ... 250
```

Clear at the far edge, the shadow fading in, then the opaque panel body. On Tauri
2.11.5 and macOS 26, with `macOSPrivateApi: true`, transparency holds. That check
still ships as the `window_report` command, because a regression in it would be
invisible to the rest of the test suite.

## What changed shape

**Widgets are iframes, not one webview each.** Tauri's multi-webview support is
behind an `unstable` flag with open bugs (webviews blank on load, broken positioning,
resize failures), so the Swift model of one `WKWebView` per widget doesn't port.
Each widget is a sandboxed iframe without `allow-same-origin`, which gives it an
opaque origin: no reach into the host page, no shared storage, no Tauri bridge.

That moves isolation from OS-level to policy-level:

| | Swift | Tauri |
| --- | --- | --- |
| Network blocking | `WKContentRuleList` | Per-widget CSP header |
| Storage isolation | `WKWebsiteDataStore` per widget | Opaque origin + bridge-keyed store |
| File isolation | Per-widget webview | **Not isolated** — see gaps |

**Geometry moved to Rust.** The frontend draws what it is told. `panel-state` carries
shape size, radii and offsets, so there is one source of truth rather than two
implementations that can drift.

**Tolerant settings decoding got shorter.** Serde's `default` does what a
hand-written 30-line decoder had to do in Swift. The older-file test came along
unchanged.

**Alignment lost an axis flip.** Tauri reports monitors with the origin at the top
left where Cocoa used the bottom left, so `alignment = 0` means top or left on every
edge without a special case.

## What works

- Transparent, shaped, always-on-top panel at `NSStatusWindowLevel`
- Four-edge docking, drag-to-reposition, snug-when-idle window sizing
- Idle handle chips: clock, date, CPU, memory, battery, now playing, clipboard,
  widget icons
- Built-in widgets: clock, system, now playing, clipboard, quick launcher
- Custom widgets: discovery, manifest validation, hot reload, per-widget CSP,
  permission gating, storage, and the full `window.notchly` surface
- Menu bar item, global hotkey, launch at login
- **54 Rust tests**, ported from the Swift suite plus new ones for the protocol

## Gaps

Honest list of what the Swift build does that this one does not yet.

**No settings window.** Settings are editable through the menu bar item and by
editing `settings.json`. This is the largest remaining piece of work.

**Windows is stubbed.** `platform.rs` has the module structure and macOS
implementation; the Windows side needs `WS_EX_NOACTIVATE | WS_EX_TOPMOST` via
`windows-rs`, and Now Playing wants
`GlobalSystemMediaTransportControlsSessionManager` — a real public API, which will be
better than the macOS AppleScript path it replaces.

**No real vibrancy.** The Swift build used `ultraThinMaterial`. A shaped transparent
window can't sit on an `NSVisualEffectView` without the blur showing as a rectangle
behind the concave corners, so "glass" is a translucent fill. This is a genuine
fidelity regression.

**Launcher has no app icons.** Extracting `.icns` and `.lnk` icons cross-platform is
real work; tiles show the app's initial instead.

**Widget files are readable across widgets.** The protocol handler cannot tell which
iframe is asking, so widget A can request widget B's files by id. Storage and
permissions are properly isolated; files are not. Widget files are user-installed
code rather than secrets, so this is low severity — but it is a regression from the
Swift build and should be closed.

**Not yet ported:** clipboard image capture, per-widget log UI, the web inspector
toggle, and the settings-window preview of the panel.

## Development

```bash
npm install
npx tauri dev                 # or: npx tauri build --bundles app
cd src-tauri && cargo test    # 54 tests, headless
```

To look at the panel — which otherwise only exists at the edge of a live display —
the app will walk itself through its states and save a PNG of each:

```bash
NOTCHLY_CAPTURE_DIR=/tmp/shots \
  src-tauri/target/release/bundle/macos/Notchly.app/Contents/MacOS/notchly
```

Frontend errors are reported to stdout rather than swallowed. That matters more than
usual here: a JS failure leaves an empty transparent window, which looks exactly like
a transparency bug.

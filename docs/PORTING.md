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
- Hover-to-open decided in Rust: a non-activating panel in an accessory app does not
  reliably deliver `mouseenter`/`mouseleave` to its web content, and the window
  resizes underneath the pointer as it opens
- Idle handle chips: clock, date, CPU, memory, battery, now playing, clipboard,
  widget icons
- Built-in widgets: clock, system, now playing, clipboard, quick launcher
- Custom widgets: discovery, manifest validation, hot reload, per-widget CSP,
  permission gating, storage, and the full `window.notchly` surface
- Menu bar item, global hotkey, launch at login
- Settings window: five panes, live panel preview, drag-to-reorder widgets and idle
  chips, per-widget permission switches, schema-driven widget settings, hotkey
  recorder, and the per-widget log
- **57 Rust tests**, ported from the Swift suite plus new ones for the protocol

## Gaps

Honest list of what the Swift build does that this one does not yet.

**Windows is written but unverified on hardware.** The window uses
`WS_EX_NOACTIVATE | WS_EX_TOPMOST | WS_EX_TOOLWINDOW`, and Now Playing goes through
`GlobalSystemMediaTransportControlsSession` — a real public API, so that side needs no
subprocess, no scripting dialect and no permission prompt, and it reports whatever
holds the media session rather than only two named apps.

None of it has run on a Windows machine. It could not even be type-checked from the
development Mac: `cargo check --target x86_64-pc-windows-msvc` gets as far as
`tauri-winres`, which needs `llvm-rc`. CI on a `windows-latest` runner compiles and
bundles it instead — that is what stands in for a compiler here, and it is the only
thing that has looked at this code.

Window *capture* stays macOS-only. It is a development aid, not a feature.

**No real vibrancy.** The Swift build used `ultraThinMaterial`. A shaped transparent
window can't sit on an `NSVisualEffectView` without the blur showing as a rectangle
behind the concave corners, so "glass" is a translucent fill and the default material
is Solid. Below about 90% opacity a fill with no blur behind it reads as a rendering
fault rather than as depth, which is why the materials sit close to opaque.

**Launcher has no app icons.** Extracting `.icns` and `.lnk` icons cross-platform is
real work; tiles show the app's initial instead.

**Widget files are readable across widgets.** The protocol handler cannot tell which
iframe is asking, so widget A can request widget B's files by id. Storage and
permissions are properly isolated; files are not. Widget files are user-installed
code rather than secrets, so this is low severity — but it is a regression from the
Swift build and should be closed.

**Not yet ported:** clipboard image capture, clipboard pinning, the web inspector
toggle, and the second time zone in the clock widget.

## Running it alongside the Swift build

Both apps live in this tree and can run at once, but they must not share state: their
slot records differ (`widgetID` versus `widgetId`), so a shared settings file means
each silently resets the other's widget list. The Tauri build therefore uses
`~/Library/Application Support/Notchly (Tauri)`. Rename it to `Notchly` in
`settings.rs` once the Swift app is retired.

Only run one at a time if you want to judge the panel — otherwise two panels dock to
the same screen edge and overlap.

## Why there is no iOS build

Tauri v2 can target iOS, so the question comes up. It does not apply here.

Notchly is a window that docks to the edge of a desktop display: it floats above other
applications, refuses focus, follows the pointer, and resizes itself as it opens. iOS
has no windows an app can position, no always-on-top layer, no pointer to hover, no
menu bar, and no global shortcut. The five built-in widgets fare no better — no menu
bar item, no clipboard history across apps, no launching other applications, and
custom widgets can be granted shell access, which iOS does not have and the App Store
would not permit.

What would survive a port is the widget format and the panel's stylesheet, and an app
built from those would not be Notchly. If something is wanted on a phone it should be
designed for one, sharing the `widget.json` contract rather than the code.

## Continuous integration

`.github/workflows/ci.yml` runs `cargo test` and `cargo clippy -D warnings` on both
macOS and Windows, and builds a bundle on each. Windows has no other verification
path from a macOS development machine, so a red build there is the only signal that
the Windows implementation is wrong.

## Development

```bash
npm install
npx tauri dev                 # or: npx tauri build --bundles app
cd core && cargo test    # 54 tests, headless
```

To look at the panel — which otherwise only exists at the edge of a live display —
the app will walk itself through its states and save a PNG of each:

```bash
NOTCHLY_CAPTURE_DIR=/tmp/shots \
  core/target/release/bundle/macos/Notchly.app/Contents/MacOS/notchly
```

The capture harness only works while the window server is actually compositing the
panel. Launched straight from the binary the app is never activated, WebKit reports
`document.visibilityState === "hidden"`, and the capture comes back fully transparent
even though the DOM is correct — so a blank PNG means "not composited", not "not
rendered". Check `document.visibilityState` before believing an empty capture.

Frontend errors are reported to stdout rather than swallowed. That matters more than
usual here: a JS failure leaves an empty transparent window, which looks exactly like
a transparency bug.

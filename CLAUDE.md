# Notchly

A notch-shaped panel that docks to any edge of the display, holds widgets, and lets
anyone drop in their own as a plain HTML/CSS/JS folder. macOS 26, Apple Silicon only.
Read `CONTEXT.md` first — it is the domain model and rulebook; its terminology is
binding.

## State of the repo

Working end to end: the panel opens, docks to all four edges, drags to reposition,
shows a configurable ambient strip while closed, and hosts five built-in widgets plus
any number of custom ones with hot reload.

61 unit tests cover the notch geometry, the window frames, drag placement, idle handle
sizing, settings decoding, permission gating, launcher search ranking, the widget
manifest format, and the formatters. They are the parts where a silent mistake would be invisible on screen — the
views themselves are not tested.

## Stack decisions (already made, do not relitigate)

- Plain committed `Notchly.xcodeproj`, generated once via `xcodegen` from `project.yml`
  and then treated as a normal checked-in project — regenerate only when files or
  targets are added, never as part of the build
- **AppKit is the composition root, not SwiftUI.** `main.swift` builds `NSApplication`
  by hand. The panel is a borderless `nonactivatingPanel` at `.statusBar` level with an
  `NSHostingView` inside; the SwiftUI `App` lifecycle gives no control over window level
  or activation, both of which this app lives or dies on
- No third-party dependencies. `WKWebView` hosts custom widgets, Carbon's
  `RegisterEventHotKey` provides the global shortcut (unlike a CGEvent tap it needs no
  Accessibility access), `SMAppService` handles launch-at-login
- Now Playing goes through `osascript` as a subprocess, not `NSAppleScript` and not the
  private MediaRemote framework. A busy player can take seconds to answer an Apple
  event, which would stall whichever thread `NSAppleScript` ran on
- App Sandbox off (`ENABLE_APP_SANDBOX = NO`) — custom widgets can be granted shell
  access, and the launcher reads other apps' bundles
- Scaffolding values (bundle ID, entitlements, Info.plist keys): `docs/ProjectSettings.md`

## Layout (modules as folders)

- `Notchly/App/` — composition root: `main.swift`, `AppDelegate` (status menu, hotkey
  wiring, first run), and `AppEnvironment`, the one service container everything else
  reaches through
- `Notchly/Models/` — value types only, no behaviour that touches the system:
  `NotchlySettings` (and its hand-written tolerant decoder), `ScreenEdge`,
  `PanelPlacement`, `IdleChip`, `WidgetSlot`, `WidgetDescriptor`, `WidgetPermission`,
  `WebWidgetManifest`, `JSONValue`
- `Notchly/Panel/` — `NotchShape` (the concave-cornered outline), `PanelGeometry`
  (settings + display → window frames), `IdleHandleLayout` (how big the closed handle
  needs to be for its chips), `NotchPanel`, `PanelController` (the open/close state
  machine and drag-to-reposition), and the panel's SwiftUI root
- `Notchly/Widgets/` — `WidgetRegistry` (the built-in descriptors and view factory),
  `Builtin/` (one file per built-in widget), `Web/` (the `WKWebView` host,
  `WebWidgetStore` folder watcher, `WebWidgetBridge`, and `WebWidgetRuntime`, which is
  the injected JavaScript)
- `Notchly/Services/` — everything that talks to the system: `SystemMetrics` (Mach and
  IOKit), `MediaController` + `AppleScriptRunner`, `ClipboardService`, `AppCatalog`,
  `HotKeyCenter`, `LoginItemManager`
- `Notchly/Persistence/` — `SettingsStore` (debounced writes) and `AppPaths`
- `Notchly/Support/` — small pure helpers with no state of their own: `Format`,
  `Color+Hex`, `HotKeyFormatter`, `Notifier`, `NSImage+PNG`, `NSScreen+Notchly`
- `Notchly/UI/` — shared SwiftUI components (`WidgetCard`, `IconButton`, `HoverRow`,
  `Charts`, `PanelSearchField`, `MarqueeText`, `FlowRow`), `IdleHandleView` (what the
  closed handle draws), and `UI/Settings/`, the settings window

## Code style

- Standard Swift formatting, 4-space indentation
- No `// MARK:` comments — a file that needs section markers needs splitting, not markers
- No `public` — this is one app target, so the modifier means nothing and reads as noise
- Use `CONTEXT.md` terminology in code rather than drifting to a synonym it avoids

## SwiftUI notes

Two things in here look like mistakes and are not. Both were bugs first.

- **Services are injected as environment objects individually**, never reached through
  `AppEnvironment`. Nested `ObservableObject`s do not propagate: a view that reads
  `environment.metrics.cpu` is observing `AppEnvironment` alone and will render once and
  then freeze. `PanelController` passes `metrics`, `media`, `clipboard`, `catalog`, and
  `registry` to `.environmentObject` in their own right, and views declare each one they
  read.
- **The panel's shadow is a blurred copy of `NotchShape`, not `.shadow()`.** A view
  containing a `Material` flattens to its bounding box for shadow purposes, so
  `.shadow()` draws a rectangle around the panel instead of following its corners.

## Testing

`xcodebuild -project Notchly.xcodeproj -scheme Notchly -destination 'platform=macOS,arch=arm64' test`

The tests deliberately avoid anything that needs a window server or a real display, so
they run headless. Pure logic that the UI depends on gets pulled out into a testable
type rather than tested through a view — `PanelPlacement`, `IdleHandleLayout`, and
`AppCatalog.rank` all exist in that shape for this reason.

`NotchlyTests/HandleRenderer.swift` is a development aid, not an assertion: it
rasterises the idle handle in each orientation to PNGs so the layout can be looked at,
which is otherwise hard for a surface that only appears at the edge of a live display.
It skips unless given somewhere to write:

```bash
TEST_RUNNER_NOTCHLY_RENDER_DIR=/tmp/render xcodebuild -project Notchly.xcodeproj \
  -scheme Notchly -destination 'platform=macOS,arch=arm64' \
  test -only-testing:NotchlyTests/HandleRenderer
```

## Roadmap

1. ~~Scaffold Xcode project + folder layout~~ done
2. ~~Notch shape, panel window, open/close state machine, four-edge docking~~ done
3. ~~Five built-in widgets~~ done
4. ~~Custom widget format, JS bridge, permissions, hot reload~~ done
5. ~~Settings window, drag-to-reposition~~ done
6. ~~Idle handle chips: clock, system readings, now playing, widget icons~~ done
7. Custom widgets contributing their own idle chip — not started
8. Multi-panel support (more than one panel on different edges) — not started

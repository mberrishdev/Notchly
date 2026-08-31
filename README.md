<p align="center">
  <img src="docs/assets/app-icon.png" width="96" alt="Notchly icon" />
  <h1 align="center">Notchly</h1>
</p>

<h3 align="center">A notch that docks to any edge of your screen, and holds whatever you want</h3>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6-orange.svg" />
  <img src="https://img.shields.io/badge/macOS-26+-blue.svg" />
  <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-lightgrey.svg" />
  <img src="https://img.shields.io/badge/dependencies-none-brightgreen.svg" />
</p>

Notchly puts a handle on the edge of your display. Rest the pointer on it and it opens
into a panel — with the same concave, bezel-hugging corners as the real notch, because
that is the point. Inside are widgets: five built in, and as many of your own as you
like.

**The handle isn't just a line.** Leave it showing the time, a now-playing indicator,
CPU and battery, or a glyph for every widget you've added — an ambient strip against the
bezel that you glance at without opening anything. Or keep it a bare sliver. Your call,
in Settings ▸ Appearance ▸ Idle handle.

**Your own widgets are just folders.** A `widget.json` and an `index.html`. Drop one in,
and it appears. Save a file, and it reloads. No recompiling, no signing, no SDK.

## Requirements

- macOS 26 (Tahoe) on Apple Silicon

## Install

```bash
git clone https://github.com/mberrishdev/Notchly.git
cd Notchly
open Notchly.xcodeproj   # ⌘R
```

Or headless:

```bash
xcodebuild -project Notchly.xcodeproj -scheme Notchly -configuration Release build
```

## What's in it

**Clock** — time, date, week number, and a second time zone.

**Now Playing** — artwork, a scrubbable progress bar, and transport for Music and
Spotify. Other players fall back to synthesised media keys, which only work if you have
separately given Notchly Accessibility access — it won't ask you for it.

**System** — CPU with a live sparkline and a user/system split, memory with real
pressure, disk, network throughput, battery with cycle count, and the three processes
currently costing you the most.

**Quick Launcher** — a pinned grid you can drag apps into, and a search field that ranks
prefix matches over initials over scattered ones, so `vsc` finds Visual Studio Code.

**Clipboard** — searchable history with pinning, image capture, and per-app attribution.
Skips anything a password manager marks as concealed.

**Yours** — see [docs/WidgetAPI.md](docs/WidgetAPI.md).

## The idle handle

Pick an ordered set of chips and the closed handle becomes a small ambient display:

| Chip | Shows |
| --- | --- |
| Time | Hours and minutes — stacked on the side edges, `14:32` on the top and bottom |
| Date | Day of the month and the weekday |
| CPU / Memory | Load, tinted amber then red as it climbs |
| Battery | Charge, with a bolt while charging |
| Now playing | Three bars that animate only while something is actually playing |
| Clipboard | How many entries are waiting |
| Widget icons | One glyph per widget in your panel |

Presets get you there in one click, and the chips reorder by dragging.

Only chips that read live values cost anything, and Settings tells you which ones those
are before you pick them. The default — just the clock — samples nothing at all. The
now-playing indicator listens for Music and Spotify's own playback notifications rather
than polling for them.

## Making it yours

- **Drag the handle** anywhere. Past the midpoint of the display it re-docks to that
  edge; along an edge it just slides. When the panel is open, the grip in its header
  does the same thing.
- **Choose what the handle shows** while closed — a line, the time, system readings,
  your widget icons, or any combination.
- **Launch at login**, from the menu bar item or Settings ▸ General.
- **Four edges**, any position along them, any size, and per-display pinning.
- **Hover, click, or hotkey** to open — with the delays under your control, and a *keep
  open* pin for when you want it to stay.
- **Glass, tinted, or solid**, with your accent colour, and a live scale model of your
  display in Settings so you can see the shape as you dial it in.

## Writing a widget

```
my-widget/
  widget.json     ← id, name, icon, height, permissions, declared settings
  index.html      ← anything you can write for a browser
```

```js
const stats = await notchly.system.stats();
document.querySelector('#cpu').textContent = Math.round(stats.cpu.total * 100) + '%';

const city = await notchly.settings.get('city');   // a real control in Settings
await notchly.storage.set('lastSeen', Date.now()); // persisted, private to you
```

Settings declared in your manifest get **native controls in Notchly's settings window** —
the same ones the built-in widgets use. Widgets are offline until you grant network
access, and shell access is off unless you turn it on for that specific widget; anything
you call without permission rejects with a message saying which switch to flip.

Three examples ship with the app and land in your widgets folder on first launch — a
pomodoro timer, a weather widget, and a shell command strip. Full reference:
[docs/WidgetAPI.md](docs/WidgetAPI.md).

## Privacy

Nothing is collected and nothing is reported. Notchly makes exactly one network request
of its own — fetching cover art from Spotify's CDN, and only while Spotify is what's
playing. Every other outbound request belongs to a widget you granted network access to.

Clipboard history is stored unencrypted in Application Support, so treat it like any
other local file. It skips anything a password manager marks as concealed.

Notchly asks for no Accessibility access: the global shortcut uses Carbon's hotkey API,
which doesn't need it. macOS will ask for Automation access the first time the Now
Playing widget looks at Music or Spotify.

## Contributing

`CONTEXT.md` is the domain model and the terminology is binding. `CLAUDE.md` covers the
layout and the decisions that aren't up for relitigating.

```bash
xcodegen generate    # after adding or moving files
xcodebuild -project Notchly.xcodeproj -scheme Notchly -destination 'platform=macOS,arch=arm64' test
```

## License

MIT

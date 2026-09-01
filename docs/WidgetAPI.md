# Writing a Notchly widget

A widget is a folder. Drop it in `~/Library/Application Support/Notchly/Widgets`, and
Notchly picks it up immediately — no restart, no rebuild, no signing.

```
my-widget/
  widget.json
  index.html
```

Save any file in the folder and the widget reloads in place. Notchly ▸ Settings ▸
Custom Widgets has a **Create** button that scaffolds this for you, and a per-widget log
so you can see errors without a console.

## widget.json

```json
{
  "id": "com.you.my-widget",
  "name": "My Widget",
  "version": "1.0.0",
  "author": "You",
  "description": "One line, shown in Settings.",
  "entry": "index.html",
  "icon": "sparkles",
  "height": 150,
  "minHeight": 60,
  "maxHeight": 400,
  "refreshInterval": 0,
  "permissions": ["system", "network"],
  "settings": [
    { "key": "city", "type": "string", "label": "City", "default": "Tbilisi" }
  ]
}
```

| Field | Notes |
| --- | --- |
| `id` | Required, must be unique. Duplicates are reported as a load error. |
| `name` | Required. |
| `entry` | Defaults to `index.html`. |
| `icon` | An SF Symbol name. Shown in the widget's header and in Settings. |
| `height` | Fixed height in points. **Omit it** and the widget auto-sizes to its content. |
| `minHeight` / `maxHeight` | Bounds applied to whichever height is in play. Default 40 and 520. |
| `refreshInterval` | Seconds between automatic reloads. `0` or absent means never. |
| `permissions` | See below. An unknown value is a load error, not a silent skip. |
| `settings` | Declared preferences. Notchly renders native controls for them. |

### Declared settings

Each entry becomes a real control in Notchly's settings window, and its value is
readable from your widget through `notchly.settings`. Supported `type` values are
`string`, `number` (with `minimum` / `maximum`), `boolean`, `select` (with `options`),
and `color`. Add `help` for a line of explanatory text under the label.

This is the same mechanism the built-in widgets use — a folder you drop in gets exactly
the same settings UI as Now Playing does.

## Permissions

| Permission | Grants | Granted |
| --- | --- | --- |
| `system` | CPU, memory, disk, network, battery, uptime | On declaration |
| `notifications` | Notification Center banners | On declaration |
| `network` | Loading remote resources and `notchly.http` | **Switch in Settings** |
| `clipboard` | Reading clipboard history | **Switch in Settings** |
| `shell` | Running commands as you | **Switch in Settings** |

Widgets are offline until network access is granted, and that's enforced with a content
blocker rather than a convention — a widget that hasn't been granted it cannot reach the
network even by loading a remote `<script>`.

`headers` is an object of strings, and `Authorization` is yours to set — that is how a
widget talks to an API that needs a token. Six headers describe the connection rather
than the request and are refused: `Connection`, `Host`, `Proxy-Authorization`,
`Proxy-Connection`, `Transfer-Encoding` and `Upgrade`.

`request` takes `GET`, `HEAD`, `POST`, `PUT`, `PATCH` or `DELETE`; `CONNECT` and `TRACE`
are refused. A string `body` is sent as written, anything else is serialised as JSON and
gets a matching `Content-Type` unless you set one yourself. Every request times out after
20 seconds, because a widget has no way to cancel its own.

**Your token is stored in plain text.** Declared settings live in Notchly's settings
file and `notchly.storage` is a JSON file beside it, neither encrypted. Ask for a token
scoped as narrowly as the API allows.

Anything you call without the necessary permission **rejects with a message explaining
which switch to flip**, so you can surface it to the user instead of rendering an empty
box. The `command-strip` example does exactly that.

## The API

Everything on `window.notchly` returns a promise.

```js
notchly.version                   // the bridge version, currently "1.0"
await notchly.call(method, params)  // escape hatch; everything below is built on it

await notchly.system.stats()      // { cpu, memory, disk, network, battery, uptime }
await notchly.system.info()       // { hostName, userName, osVersion, appearance }

await notchly.settings.get('city')
await notchly.settings.all()

await notchly.storage.set('count', 3)   // persisted, private to this widget
await notchly.storage.get('count')
await notchly.storage.remove('count')
await notchly.storage.keys()
await notchly.storage.clear()

await notchly.media.now()         // { playing, title, artist, album, duration, position }
await notchly.media.playPause()
await notchly.media.next()
await notchly.media.previous()

await notchly.clipboard.history(20)
await notchly.clipboard.write('text')

await notchly.http.get(url, headers)       // { status, body }
await notchly.http.json(url, headers)      // the same, parsed
await notchly.http.post(url, body, headers)
await notchly.http.request({ url, method, headers, body })

await notchly.shell.run('uptime', 8)    // { code, stdout, stderr }

await notchly.open('https://example.com')
await notchly.notify('Title', 'Body')
await notchly.log('anything', { debug: true })   // shows in Settings ▸ Custom Widgets

await notchly.ui.resize(220)      // set your height explicitly
await notchly.ui.autoHeight(true) // or measure it continuously
await notchly.ui.holdOpen(true)   // stop the panel closing mid-interaction
await notchly.ui.close()
await notchly.ui.theme()

notchly.on('theme', (theme) => { /* … */ })
```

`notchly.ui.holdOpen(true)` matters more than it looks: without it, a panel set to close
on pointer-exit will slide shut while someone is typing into your widget.

## Styling

Notchly injects CSS custom properties on `:root` and updates them live when the user
changes the accent colour:

```css
--notchly-accent
--notchly-text  --notchly-text-secondary  --notchly-text-tertiary
--notchly-surface  --notchly-surface-hover
--notchly-hairline
--notchly-radius
--notchly-font
--notchly-appearance    /* "dark" or "light" */
```

The page background is transparent and sits on Notchly's card, so don't paint your own
unless you mean to. A minimal stylesheet (system font, hidden scrollbars, sane focus
ring) is injected as the *first* stylesheet, so any rule you write wins.

## Bundled examples

Four ship with the app and are copied into your widgets folder on first launch. They
are meant to be read and pulled apart:

- **pomodoro** — declared settings, persistent storage, notifications. Stores an end
  timestamp rather than a countdown, so it stays correct across restarts.
- **weather** — the network permission, using Open-Meteo with no API key.
- **up-next** — parsing a real feed. Reads an iCalendar `.ics` URL and shows the next few
  events, including recurring ones.
- **command-strip** — the shell permission, including how to handle being denied it.

Settings ▸ Custom Widgets ▸ **Reinstall Examples** restores them if you edit them into a
corner.

## Debugging

`console.error` and uncaught errors are mirrored into the per-widget log in
Settings ▸ Custom Widgets, so you can debug without a console.

## Isolation

Your widget runs in a sandboxed iframe with an opaque origin. It cannot reach the host
page, the Tauri bridge, or another widget's storage — everything it can do arrives
through `window.notchly`, which checks your granted permissions first. Your widget's
*files* are readable by other widgets; file-level isolation is not yet implemented.

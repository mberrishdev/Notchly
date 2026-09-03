# Notchly — domain model

This file is the rulebook. Its terminology is binding: use these words in type names,
tests, and commits rather than drifting to a synonym listed under "avoid".

## The Panel

The **Panel** is the single notch-shaped surface Notchly draws. It is not a window in
the user's mental model — it is a piece of the display's bezel that opens.

It has exactly two visual states:

- **Idle** — the **Handle** hugging the screen edge. Either a bare line, or a strip
  showing **Idle Chips** (see below).
- **Open** — the surface the Handle opens into, in whichever **Panel Style** is set.

There is no third state. Anything that looks like a third state (a hover highlight, a
drag lift, a **Popover**) is a decoration on one of these two.

The Panel's outline is the **Notch Shape**: rounded on the two corners away from the
screen edge, and *concave* on the two corners that meet it, flaring outward so the
surface reads as continuous with the bezel. The concave corners are the whole point of
the app's identity — never replace the shape with a plain rounded rectangle.

- Avoid: "popover", "HUD", "drawer", "sidebar", "window" (for the Panel itself). The
  Popover below is a real thing with that name; the Panel is never called one.

**`shows_handle_when_idle` is what makes Notchly disappear.** Turned off, the Handle is
the bare line whatever Idle Chips are selected — the selection is kept, not cleared, so
turning it back on restores the strip that was there. The Panel window is snug around
the line, so what is left on screen is a few points of bezel that swallows nothing.

## Panel Style

Which surface the Panel opens into. Two, and the Panel is Open in both:

- **Full** — the **Widget Stack**: every enabled Slot's card, one under another, in a
  Panel sized by the width and height settings.
- **Compact** — the **Icon Strip**: one **Widget Icon** per enabled Slot, plus a
  settings action, on a surface barely larger than the Handle. Resting on an icon draws
  that widget's **Popover** beside the strip.

Rules:

1. **The Icon Strip is a row of targets, not a canvas.** Its size comes from
   `StripLayout` and the number of icons, never from the panel width and height
   settings — a wider strip would only spread the icons further apart.
2. **The settings action leads the strip**, so its position never moves as widgets are
   added and removed.
3. **A widget shows the same view in both Styles.** A Built-in Widget's Popover calls
   the same function the Stack calls; a Custom Widget's is the same sandboxed iframe
   under the same origin. A widget that rendered differently in the two would be two
   widgets.
4. **Compact reserves the Popover's room in the window frame.** The strip's window is
   sized for the strip *plus* a Popover beside it, whether or not one is showing, so a
   Popover never appears outside the window and gets clipped.

## The Popover

The card drawn beside the Panel while the pointer rests on something: an Idle Chip that
draws an arc, or a Widget Icon on the Icon Strip. One gesture, one state — only one
Popover shows at a time, and Rust owns which, because the Panel never activates and so
cannot be asked from the DOM.

1. **A Popover is drawn clear of the hover buffer, not merely clear of the shape.** The
   buffer counts as part of the Handle, so a Popover inside it had a near edge that read
   as "still on the Handle" — which put it away in the same motion that reached for it.
   `popover_offset` is that distance, and the frontend is handed it rather than choosing
   one.
2. **Reaching onto a Popover is not the push that opens the Panel.** The room it
   occupies is its own zone; only past it is the movement unambiguous.
3. **Opening the Widget Stack supersedes a Popover**, which would otherwise be drawn
   behind it. The Icon Strip is the exception, being the size of a Handle.

## Idle Chips

An **Idle Chip** is one reading the Handle shows while the Panel is closed — the time,
CPU load, a now-playing indicator, the glyphs of the widgets inside. The user picks an
ordered list of them; an empty list is the bare line.

Two rules make the Handle stable:

1. **A chip reserves its space whether or not it currently has a value.** Space is
   computed from `IdleChip::extent`, never measured after layout. A Handle that resized
   itself when a song started would move the drag target out from under the pointer.
2. **Chips render for their orientation, they are never rotated.** On the left and right
   Edges they stack in a column and lay out vertically (the clock becomes two lines); on
   the top and bottom they sit in a row. Rotated text is unreadable at this size.

`HandleLayout` owns the arithmetic and is the single source of truth for the
Handle's size — the real Panel and the Settings preview both go through it.

## Placement

- **Edge** — which side the Panel docks to: `leading`, `trailing`, `top`, `bottom`.
  Named for the side of the *display*, not for the direction the Panel grows.
- **Alignment** — where along the Edge the Panel sits, `0`…`1`. `0` is the top for the
  left and right Edges, the left for the top and bottom Edges.
- **Placement** — an Edge plus an Alignment. `Placement::resolve` derives one from
  a pointer position; it is the single source of truth for drag-to-reposition.

`ScreenEdge::grows_horizontally` is true for `leading` and `trailing`. It describes the
Panel's growth direction, not the orientation of the edge. Do not rename it to
`isHorizontal` — that reading is backwards and has already caused one bug.

## Window rules

These are load-bearing, not preferences:

1. **The Panel window is snug when Idle.** It is sized to the Handle plus a small hover
   buffer, and only grows to the full footprint while Open. An always-large transparent
   window would silently swallow every click aimed at the desktop behind it.
2. **The window frame changes before the animation, never during it.** Opening sets the
   full frame immediately (invisibly, since the window is transparent) and the frontend
   then animates the shape inside it. Animating the frame itself judders.
3. **Both states share one centre along the Edge.** Clamping the centre against the
   Idle Handle's extent when closed and the open Panel's when open put them in
   different places, so the Panel slid along its Edge as it opened. It grows in place.
4. **The Panel never activates the app on hover.** It takes focus only on an explicit
   hotkey, click, or tap — never because the pointer passed over it. Consequently it
   cannot rely on the web view receiving pointer events, so hover is decided from the
   cursor position in Rust rather than in the DOM.
5. **The Panel is opaque.** A shaped window cannot sit on a real backdrop blur without
   the blur showing as a rectangle behind the concave corners, and a translucent fill
   with nothing behind it reads as a rendering fault rather than as depth.

## Widgets

A **Widget** is one entry in the user's Panel — a card in the Widget Stack, or an icon
and its Popover on the Icon Strip. Two kinds, and the distinction is only about where
the code lives:

- **Built-in Widget** — compiled in. Clock, Now Playing, System, Quick Launcher,
  Clipboard.
- **Custom Widget** — a folder the user dropped into the **Widgets Folder**
  (`~/Library/Application Support/Notchly/Widgets`). Contains a **Manifest**
  (`widget.json`) and an HTML entry point. Loaded into a sandboxed iframe under its
  own `widget://` origin. No recompiling.

Both kinds are described by a **Widget Descriptor** — one uniform record carrying name,
symbol, summary, declared settings, and requested permissions. Every piece of UI that
lists or configures widgets consumes Descriptors, so a Custom Widget gets exactly the
same native settings controls as a Built-in one. Do not add a Custom-Widget-only code
path to the settings UI.

- **Slot** — one entry in the user's Panel: a widget id, an order, an enabled flag, and
  that widget's preference values. The user's Panel is an ordered list of Slots, not a
  list of Widgets.
- **Widget Package** — a Manifest plus its folder, once successfully loaded.
- Avoid: "plugin", "extension", "module", "applet".

## The Bridge

**The Bridge** is `window.notchly`, injected into every Custom Widget. Rules:

1. Every Bridge call returns a promise. A widget posts to the host page, which checks
   its permissions and forwards to Rust; the widget never sees that plumbing.
2. **A permission the widget didn't declare, or the user didn't grant, rejects with a
   readable message.** It never returns empty data or fails silently — the widget author
   must be able to see why nothing happened.
3. **Custom Widgets are offline until granted.** Network access is enforced with a
   a Content-Security-Policy served with every response, not by asking politely.
4. **`WidgetPermission.requiresExplicitGrant` is the only list of what the user has to
   approve by hand** — currently `network`, `clipboard`, and `shell`. Enforcement, the
   Settings toggles, and a widget's lock badge all read that one property. When the
   three disagreed, clipboard history was readable by any widget that asked for it.
6. **A Bridge call is attributed to whichever iframe sent it**, never to a widget id in
   the message body — otherwise any widget could claim to be another and borrow its
   permissions. Each Custom Widget has an opaque origin and its own key/value store, so
   one cannot read another's state. Their *files* are not yet isolated.

## Sampling

Everything that samples — system metrics, now playing — is **refcounted**, at one of two
**Cadences**:

- **Live** — the numbers are on screen. Fast.
- **Ambient** — the Panel is closed but an Idle Chip needs the value. Slow.

An open Widget Stack is Live because it shows every widget at once. **An open Icon Strip
is not**: it puts nothing on screen but glyphs, so only the Popover the pointer actually
opened counts as a reading being displayed.

The fastest requested Cadence wins; no subscribers stops sampling entirely, which is the
default state, because the default Handle shows only the clock and the clock samples
nothing. A chip that costs something says so in Settings before the user picks it.

Prefer being told over asking: the now-playing indicator subscribes to Music's and
Spotify's distributed notifications and only polls when one fires, so an Ambient
subscription to it spawns no recurring work.

The Clipboard watcher is the one thing outside this scheme — it must run whenever the
app does, because a history with gaps in it is not a history.

// The Strip: what the Panel opens into.
//
// One Row per enabled widget, each carrying its own headline reading rather than a bare
// glyph — the Strip is meant to be read at a glance, and an icon on its own says only
// that a widget exists. Resting on a Row opens that widget's Popover for the detail.
//
// A Row reserves the same room whether or not its reading currently has a value, for
// the reason an Idle Chip does: a Strip that resized itself when a song started would
// move the drag target out from under the pointer. That is why every value here is
// rendered into a fixed box and never measured.
//
// Row sizes come from the metrics Rust pushed. It measured the Strip against them and
// decides which Row the pointer is on, so deriving a size here would open the Popover
// for the wrong widget.
//
// The Rows are built once and then updated in place. Rebuilding them restarted their
// slide-in animation, and because a render happens on every metrics tick and every
// change of which Popover is open, the whole Strip flickered a few times a second.
// Structure changes when the widgets do; readings change constantly.

import { growsHorizontally } from "./notch-shape.js";
import { icons, widgetGlyph } from "./icons.js";

const pad = (value) => String(value).padStart(2, "0");
const percent = (fraction) => `${Math.round((fraction ?? 0) * 100)}%`;

/** Tone for a load reading: quiet until it matters, then amber, then red. */
function loadTone(fraction) {
  if (fraction < 0.6) return "normal";
  if (fraction < 0.85) return "caution";
  return "danger";
}

/**
 * The one reading a widget puts on its Row.
 *
 * `kind` is fixed per widget and decides what element the Row is built with; only the
 * value inside it changes afterwards. `bars` exists because "is something playing" is
 * not a number, and says it far better than a title truncated to four characters would.
 * A widget with nothing worth reducing to one reading is `none` and shows its glyph
 * alone.
 */
function reading(widgetId, data) {
  const metrics = data.metrics ?? {};
  switch (widgetId) {
    case "clock": {
      const now = new Date();
      return { kind: "text", value: `${pad(now.getHours())}:${pad(now.getMinutes())}` };
    }
    case "system":
      return { kind: "text", value: percent(metrics.cpu), tone: loadTone(metrics.cpu ?? 0) };
    case "media":
      return { kind: "bars", playing: Boolean(data.media?.playing) };
    case "clipboard":
      return { kind: "text", value: String(data.clipboardCount ?? 0) };
    default:
      return { kind: "none" };
  }
}

/** The Rows the Strip should have, in order. The settings action always leads. */
function rowsFor(settings) {
  return [
    { key: "settings", glyph: icons.settings, kind: "none" },
    ...settings.slots
      .filter((slot) => slot.isEnabled)
      .map((slot) => ({
        key: slot.widgetId,
        glyph: widgetGlyph(slot.widgetId),
        kind: reading(slot.widgetId, {}).kind,
      })),
  ];
}

function buildRow(spec, stacked, along, title) {
  const row = document.createElement("button");
  row.className = "strip-row";
  row.dataset.row = spec.key;
  row.title = title;
  row.style[stacked ? "height" : "width"] = along;

  const glyph = document.createElement("span");
  glyph.className = "row-glyph";
  glyph.innerHTML = spec.glyph;
  row.append(glyph);

  if (spec.kind === "text") {
    const value = document.createElement("span");
    value.className = "row-value";
    row.append(value);
  } else if (spec.kind === "bars") {
    const bars = document.createElement("span");
    bars.className = "row-bars";
    bars.innerHTML = '<span class="bar"></span><span class="bar"></span><span class="bar"></span>';
    row.append(bars);
  }
  return row;
}

export function renderStrip(container, settings, metrics, data, active, nameOf) {
  const stacked = growsHorizontally(settings.edge);
  const specs = rowsFor(settings);
  const along = `${metrics.stripRowExtent}px`;
  // Everything a Row is *built* from. Readings are deliberately absent: they change on
  // every tick, and a signature that included them would rebuild the Strip constantly.
  const signature = `${settings.edge}:${metrics.stripRowExtent}:${specs.map((s) => s.key).join("|")}`;

  if (container.dataset.signature !== signature) {
    container.dataset.signature = signature;
    container.className = stacked ? "strip stacked" : "strip";
    container.replaceChildren(
      ...specs.map((spec) => buildRow(spec, stacked, along, nameOf(spec.key))),
    );
  }

  for (const [index, spec] of specs.entries()) {
    const row = container.children[index];
    if (!row) continue;
    // Marked from the state Rust pushed, never from :hover, so the highlight and the
    // Popover cannot disagree about which Row is open.
    if (spec.key === active) {
      row.dataset.active = "true";
    } else {
      delete row.dataset.active;
    }
    if (spec.kind === "none") continue;

    const read = reading(spec.key, data);
    if (read.kind === "text") {
      const value = row.querySelector(".row-value");
      if (value) {
        value.textContent = read.value;
        value.className = `row-value tone-${read.tone ?? "normal"}`;
      }
    } else if (read.kind === "bars") {
      row.querySelector(".row-bars")?.classList.toggle("playing", read.playing);
    }
  }
}

/**
 * Forgets the Rows on screen, so the next open rebuilds and slides them in again.
 *
 * Called when the Panel closes: its children stay in the DOM while hidden, and without
 * this the Strip would reappear already in place, having only ever animated once.
 */
export function resetStrip(container) {
  delete container.dataset.signature;
}

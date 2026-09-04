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
 * `value` is drawn as text; `html` when the reading is not a number — the now-playing
 * bars are the only one, and they say "playing" far better than a title truncated to
 * four characters would. A widget with nothing worth reducing to one reading returns
 * null and shows its glyph alone.
 */
function reading(widgetId, data) {
  const metrics = data.metrics ?? {};
  switch (widgetId) {
    case "clock": {
      const now = new Date();
      return { value: `${pad(now.getHours())}:${pad(now.getMinutes())}` };
    }
    case "system":
      return { value: percent(metrics.cpu), tone: loadTone(metrics.cpu ?? 0) };
    case "media":
      return {
        html: `<span class="row-bars ${data.media?.playing ? "playing" : ""}">
          <span class="bar"></span><span class="bar"></span><span class="bar"></span>
        </span>`,
      };
    case "clipboard":
      return { value: String(data.clipboardCount ?? 0) };
    default:
      return null;
  }
}

export function renderStrip(container, settings, metrics, data, active, nameOf) {
  const stacked = growsHorizontally(settings.edge);
  container.className = stacked ? "strip stacked" : "strip";
  container.replaceChildren();

  // Along the edge every Row is the size Rust measured; across it they fill the strip.
  const along = `${metrics.stripRowExtent}px`;

  const add = (key, glyph, title, body) => {
    const row = document.createElement("button");
    row.className = "strip-row";
    row.dataset.row = key;
    row.title = title;
    row.style[stacked ? "height" : "width"] = along;
    row.innerHTML = `<span class="row-glyph">${glyph}</span>${body ?? ""}`;
    if (key === active) row.dataset.active = "true";
    container.append(row);
  };

  add("settings", icons.settings, "Settings");
  for (const slot of settings.slots.filter((slot) => slot.isEnabled)) {
    const read = reading(slot.widgetId, data);
    const body = read?.html
      ? read.html
      : read
        ? `<span class="row-value tone-${read.tone ?? "normal"}">${read.value}</span>`
        : "";
    add(slot.widgetId, widgetGlyph(slot.widgetId), nameOf(slot.widgetId), body);
  }
}

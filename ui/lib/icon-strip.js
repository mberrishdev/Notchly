// The compact panel: a row of icons against the bezel, one per enabled widget.
//
// This is an Open state, not a decorated handle — the panel really is open, it just
// has nothing on it but targets. Resting on one draws that widget's popover beside the
// strip; the settings icon leads the row so its position never moves as widgets come
// and go.
//
// The icon boxes are sized from `stripIconExtent`, which Rust measured the strip
// against and uses to decide which icon the pointer is on. Choosing a size here would
// let the two disagree, and the card would open for the wrong widget.

import { growsHorizontally } from "./notch-shape.js";
import { icons, widgetGlyph } from "./icons.js";

export function renderIconStrip(container, settings, metrics, active, nameOf) {
  const stacked = growsHorizontally(settings.edge);
  const size = `${metrics.stripIconExtent}px`;
  container.className = stacked ? "icon-strip stacked" : "icon-strip";
  container.replaceChildren();

  const add = (key, glyph, title) => {
    const button = document.createElement("button");
    button.className = "strip-icon";
    button.dataset.icon = key;
    button.title = title;
    button.style.width = size;
    button.style.height = size;
    button.innerHTML = glyph;
    if (key === active) button.dataset.active = "true";
    container.append(button);
  };

  add("settings", icons.settings, "Settings");
  for (const slot of settings.slots.filter((slot) => slot.isEnabled)) {
    add(slot.widgetId, widgetGlyph(slot.widgetId), nameOf(slot.widgetId));
  }
}

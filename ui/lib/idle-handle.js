// What the panel shows while it is closed.
//
// The handle is a strip against the bezel, so the layout flips axis with the edge:
// chips stack in a column on the left and right, and sit in a row on the top and
// bottom. Each chip renders differently in the two orientations rather than being
// rotated, because rotated text is unreadable at this size.

import { growsHorizontally } from "./notch-shape.js";
import { icons, widgetGlyph } from "./icons.js";

const pad = (value) => String(value).padStart(2, "0");

function clockChip(stacked, metrics) {
  const now = new Date();
  const hour = pad(now.getHours());
  const minute = pad(now.getMinutes());
  if (stacked) {
    return `<div class="chip chip-clock stacked">
      <span class="primary">${hour}</span><span class="secondary">${minute}</span>
    </div>`;
  }
  return `<div class="chip chip-clock"><span class="primary">${hour}:${minute}</span></div>`;
}

function dateChip(stacked) {
  const now = new Date();
  const day = now.getDate();
  const weekday = now.toLocaleDateString("en-US", { weekday: "short" });
  return stacked
    ? `<div class="chip stacked"><span class="primary">${day}</span><span class="tertiary small">${weekday}</span></div>`
    : `<div class="chip"><span class="tertiary small">${weekday}</span><span class="primary">${day}</span></div>`;
}

/**
 * A reading whose value is a fraction of a known whole, drawn as an arc.
 *
 * The arc carries the glance and the number carries the detail. At handle size a bare
 * percentage has to be stopped at and read, while a ring's fill is legible in passing —
 * and a colour change is visible without reading anything at all.
 *
 * `ring` arrives from Rust rather than being computed here: it is the diameter the
 * handle was measured against, so deriving a second one would let the strip's size and
 * its contents disagree.
 */
function arcChip(icon, fraction, tone, stacked, ring) {
  const value = Math.min(1, Math.max(0, fraction ?? 0));
  const stroke = Math.max(2, ring * 0.08);
  const radius = (ring - stroke) / 2;
  const circumference = 2 * Math.PI * radius;
  const filled = circumference * value;
  const mid = ring / 2;
  // Sized in pixels, not a percentage: the glyph's parent is shrink-to-fit, so a
  // percentage there resolves against a box that is itself sized by this element.
  const glyph = Math.round(ring * 0.5);
  return `<div class="chip chip-arc ${stacked ? "stacked" : ""} tone-${tone}">
    <span class="arc-well" style="width:${ring}px;height:${ring}px">
      <svg class="arc-rings" viewBox="0 0 ${ring} ${ring}" width="${ring}" height="${ring}" aria-hidden="true">
        <circle class="arc-track" cx="${mid}" cy="${mid}" r="${radius}" fill="none" stroke-width="${stroke}"/>
        <circle class="arc-value" cx="${mid}" cy="${mid}" r="${radius}" fill="none" stroke-width="${stroke}"
                stroke-linecap="round" transform="rotate(-90 ${mid} ${mid})"
                stroke-dasharray="${filled.toFixed(2)} ${(circumference - filled).toFixed(2)}"/>
      </svg>
      <span class="glyph" style="width:${glyph}px;height:${glyph}px">${icon}</span>
    </span>
    <span class="value">${percent(value)}</span>
  </div>`;
}

/** A reading with no whole to be a fraction of: text, and no ring drawn around nothing. */
function readingChip(icon, value, tone, stacked) {
  return `<div class="chip ${stacked ? "stacked" : ""} tone-${tone}">
    <span class="glyph">${icon}</span><span class="value">${value}</span>
  </div>`;
}

export function loadTone(fraction) {
  if (fraction < 0.6) return "normal";
  if (fraction < 0.85) return "caution";
  return "danger";
}

export const percent = (fraction) => `${Math.round((fraction ?? 0) * 100)}%`;

function nowPlayingChip(media) {
  const playing = Boolean(media?.playing);
  return `<div class="chip chip-media ${playing ? "playing" : ""}">
    <span class="bar"></span><span class="bar"></span><span class="bar"></span>
  </div>`;
}

function widgetIconsChip(widgetIds, stacked) {
  const glyphs = (widgetIds.length ? widgetIds : [null]).map(widgetGlyph);
  return `<div class="chip chip-icons ${stacked ? "stacked" : ""}">
    ${glyphs.map((glyph) => `<span class="glyph">${glyph}</span>`).join("")}
  </div>`;
}

export function renderIdleHandle(container, settings, data, ring) {
  const stacked = growsHorizontally(settings.edge);
  const metrics = data.metrics ?? {};
  const html = (settings.handleChips ?? [])
    .map((chip) => {
      switch (chip) {
        case "clock":
          return clockChip(stacked, metrics);
        case "date":
          return dateChip(stacked);
        case "cpu":
          return arcChip(icons.cpu, metrics.cpu, loadTone(metrics.cpu ?? 0), stacked, ring);
        case "memory":
          return arcChip(icons.memory, metrics.memory, loadTone(metrics.memory ?? 0), stacked, ring);
        case "battery":
          return batteryChip(metrics.battery, stacked, ring);
        case "nowPlaying":
          return nowPlayingChip(data.media);
        case "clipboard":
          return readingChip(icons.clipboard, String(data.clipboardCount ?? 0), "normal", stacked);
        case "widgetIcons":
          return widgetIconsChip(data.widgetIcons ?? [], stacked);
        default:
          return "";
      }
    })
    .join("");

  container.className = stacked ? "idle-handle stacked" : "idle-handle";
  container.innerHTML = html;
}

function batteryChip(battery, stacked, ring) {
  // A machine with no battery reads 0%, which must not be drawn as an empty ring —
  // there is no charge to be a fraction of, so it falls back to a plain reading.
  if (!battery?.present) return readingChip(icons.power, "AC", "muted", stacked);
  const level = battery.level ?? 0;
  const tone = battery.charging ? "good" : level < 0.15 ? "danger" : level < 0.3 ? "caution" : "normal";
  return arcChip(battery.charging ? icons.charging : icons.battery, level, tone, stacked, ring);
}

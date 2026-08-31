// What the panel shows while it is closed.
//
// The handle is a strip against the bezel, so the layout flips axis with the edge:
// chips stack in a column on the left and right, and sit in a row on the top and
// bottom. Each chip renders differently in the two orientations rather than being
// rotated, because rotated text is unreadable at this size.

import { growsHorizontally } from "./notch-shape.js";
import { icons } from "./icons.js";

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

function readingChip(icon, value, tone, stacked) {
  return `<div class="chip ${stacked ? "stacked" : ""} tone-${tone}">
    <span class="glyph">${icon}</span><span class="value">${value}</span>
  </div>`;
}

function loadTone(fraction) {
  if (fraction < 0.6) return "normal";
  if (fraction < 0.85) return "caution";
  return "danger";
}

const percent = (fraction) => `${Math.round((fraction ?? 0) * 100)}%`;

function nowPlayingChip(media) {
  const playing = Boolean(media?.playing);
  return `<div class="chip chip-media ${playing ? "playing" : ""}">
    <span class="bar"></span><span class="bar"></span><span class="bar"></span>
  </div>`;
}

const WIDGET_GLYPHS = {
  clock: icons.clock,
  media: icons.charging,
  system: icons.cpu,
  launcher: icons.widget,
  clipboard: icons.clipboard,
};

function widgetIconsChip(widgetIds, stacked) {
  const glyphs = (widgetIds.length ? widgetIds : [null]).map(
    (id) => WIDGET_GLYPHS[id] ?? icons.widget,
  );
  return `<div class="chip chip-icons ${stacked ? "stacked" : ""}">
    ${glyphs.map((glyph) => `<span class="glyph">${glyph}</span>`).join("")}
  </div>`;
}

export function renderIdleHandle(container, settings, data) {
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
          return readingChip(icons.cpu, percent(metrics.cpu), loadTone(metrics.cpu ?? 0), stacked);
        case "memory":
          return readingChip(icons.memory, percent(metrics.memory), loadTone(metrics.memory ?? 0), stacked);
        case "battery":
          return batteryChip(metrics.battery, stacked);
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

function batteryChip(battery, stacked) {
  // A machine with no battery reads 0%, which must not be shown as critical.
  if (!battery?.present) return readingChip(icons.power, "AC", "muted", stacked);
  const level = battery.level ?? 0;
  const tone = battery.charging ? "good" : level < 0.15 ? "danger" : level < 0.3 ? "caution" : "normal";
  return readingChip(battery.charging ? icons.charging : icons.battery, percent(level), tone, stacked);
}

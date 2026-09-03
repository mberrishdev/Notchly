// The popover drawn beside the panel while the pointer rests on something.
//
// Two things can be rested on, and they produce the same popover: a reading on the idle
// handle, and a widget icon on the compact strip. Rust decides which — the panel never
// activates, so the DOM cannot be asked — and this only draws what it is told.
//
// A widget's popover is the widget's own view, not a second smaller implementation of it.
// The built-ins reuse the very functions the widget stack renders, and a custom widget
// gets the same sandboxed iframe under its own origin. A widget that behaved
// differently in the two places would be two widgets.

import { icons, widgetGlyph } from "./icons.js";
import { loadTone, percent } from "./idle-handle.js";
import * as builtin from "./builtin-widgets.js";
import { createWidgetCard, trackManifest } from "./widget-host.js";

/** One labelled bar in a popover. */
function meter(label, fraction, tone) {
  const value = Math.min(1, Math.max(0, fraction ?? 0));
  return `<div class="pop-row">
    <div class="pop-line"><span class="pop-label">${label}</span><span class="pop-value">${percent(value)}</span></div>
    <div class="pop-track"><span class="pop-fill tone-${tone}" style="width:${(value * 100).toFixed(1)}%"></span></div>
  </div>`;
}

/**
 * The detail behind one reading on the idle handle.
 *
 * Only the readings that draw an arc get one — they are the ones with more to say than
 * the number already on screen. Anything else opens the panel instead, as it always has.
 */
export function chipContent(chip, data) {
  const metrics = data.metrics ?? {};
  if (chip === "battery") {
    const battery = metrics.battery ?? {};
    const level = battery.level ?? 0;
    const tone = battery.charging ? "good" : level < 0.15 ? "danger" : level < 0.3 ? "caution" : "normal";
    const state = battery.charging ? "Charging" : "On battery";
    const detail = battery.minutesRemaining
      ? `${Math.round(battery.minutesRemaining / 60)}h ${battery.minutesRemaining % 60}m ${battery.charging ? "to full" : "left"}`
      : state;
    return `<div class="pop-head"><span class="glyph">${battery.charging ? icons.charging : icons.battery}</span>Battery</div>
      ${meter("Charge", level, tone)}
      <div class="pop-foot"><span>${state}</span><span class="pop-strong">${detail}</span></div>`;
  }

  const heaviest = metrics.topProcesses?.[0];
  return `<div class="pop-head"><span class="glyph">${icons.cpu}</span>System</div>
    ${meter("CPU", metrics.cpu, loadTone(metrics.cpu ?? 0))}
    ${meter("Memory", metrics.memory, loadTone(metrics.memory ?? 0))}
    ${meter("Disk", metrics.disk, "muted")}
    ${heaviest ? `<div class="pop-foot"><span>Heaviest right now</span><span class="pop-strong">${heaviest.name}</span></div>` : ""}`;
}

/** The built-ins, keyed the same way the widget stack keys them. */
const BUILTIN_CARDS = {
  clock: (ctx) => builtin.clockWidget(ctx.prefs),
  system: (ctx) => builtin.systemWidget(ctx.ambient.metrics ?? {}, ctx.cpuHistory, ctx.prefs),
  media: (ctx) => builtin.mediaWidget(ctx.ambient.media),
  clipboard: (ctx) => builtin.clipboardWidget(ctx.clipboard, ctx.prefs),
  launcher: () => builtin.launcherWidget(),
};

/**
 * True for the popovers worth rebuilding on every tick.
 *
 * The rest own something a rebuild would throw away — the launcher's typed query, a
 * custom widget's whole iframe — so they are built once and left alone.
 */
export function contentRefreshes(widgetId) {
  return widgetId in BUILTIN_CARDS && widgetId !== "launcher";
}

/** What a widget's header says on the right, when a single number is worth the room. */
const HEADER_ACCESSORY = {
  clipboard: (ctx) => String(ctx.clipboard?.length ?? 0),
};

/** A titled popover for one widget: the name, then the widget's own view under it. */
export function widgetContent(widgetId, ctx) {
  const wrap = document.createElement("div");
  wrap.className = "pop-widget";

  const head = document.createElement("div");
  head.className = "pop-head";
  head.innerHTML = `<span class="glyph">${widgetGlyph(widgetId)}</span>`;
  head.append(document.createTextNode(ctx.name(widgetId)));
  const accessory = HEADER_ACCESSORY[widgetId]?.(ctx);
  if (accessory != null) {
    const count = document.createElement("span");
    count.className = "pop-head-accessory";
    count.textContent = accessory;
    head.append(count);
  }
  wrap.append(head);

  const build = BUILTIN_CARDS[widgetId];
  if (build) {
    wrap.append(build(ctx));
    return wrap;
  }

  const pkg = ctx.package(widgetId);
  if (!pkg) {
    const missing = document.createElement("div");
    missing.className = "pop-foot";
    missing.textContent = "This widget is no longer installed.";
    wrap.append(missing);
    return wrap;
  }
  const card = createWidgetCard(pkg, { onReload: ctx.onReload });
  trackManifest(card, pkg.manifest);
  wrap.append(card);
  return wrap;
}

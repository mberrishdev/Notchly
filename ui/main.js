import { panel, listen, invoke } from "./lib/bridge.js";
import { renderShape } from "./lib/panel-view.js";
import { renderIdleHandle } from "./lib/idle-handle.js";
import { renderStrip, resetStrip } from "./lib/strip.js";
import { chipContent, widgetContent, contentRefreshes } from "./lib/popover.js";
import * as builtin from "./lib/builtin-widgets.js";
import { startBridgeRelay, forgetFrames } from "./lib/widget-host.js";

/** Latest state pushed from Rust. Rust owns the window; this owns what's drawn in it. */
let current = null;
/** Live values for the idle chips, refreshed only while something needs them. */
let ambient = { metrics: {}, media: null, clipboardCount: 0, widgetIcons: [] };
let catalog = { packages: [], failures: [] };
let descriptors = [];
let clipboard = [];
let cpuHistory = new Array(48).fill(0);
/// The popover's contents are rebuilt only when they change to a different thing, for
/// the same reason: a custom widget's iframe and the launcher's typed query do not
/// survive being recreated.
let popoverSignature = "";
let launcherResults = [];
let launcherSelection = 0;

let dragging = false;
let dragStart = null;

function render() {
  if (!current) return;
  const { metrics, settings } = current;

  // The widget-icons chip draws one glyph per enabled widget.
  ambient.widgetIcons = settings.slots.filter((slot) => slot.isEnabled).map((slot) => slot.widgetId);

  const swapContent = () => {
    const handle = document.getElementById("idle-handle");
    const strip = document.getElementById("strip");
    if (metrics.expanded) {
      handle.hidden = true;
      strip.hidden = false;
      renderStrip(strip, settings, metrics, ambient, current.popover?.value, widgetName);
    } else {
      strip.hidden = true;
      resetStrip(strip);
      handle.hidden = !metrics.showsContent;
      if (metrics.showsContent) renderIdleHandle(handle, settings, ambient, metrics.handleRing);
    }
  };

  // Drawn outside the content swap: that is deliberately delayed until part-way
  // through the open animation, which left the popover painted over the panel as it
  // grew. Whether a card is showing is a state, not a stage of the animation.
  renderPopover();
  renderShape(metrics, settings, swapContent);
}

/**
 * Places the popover beside the shape, in the room the enlarged window buys.
 *
 * Rust decides whether one is showing and for what; this only draws it. The position
 * comes from the same metrics the shape is drawn from, so the card tracks the shape
 * rather than guessing where it ended up — and the gap comes from Rust too, because it
 * is the same number the hover zones are measured against.
 */
function renderPopover() {
  const node = document.getElementById("popover");
  if (!node) return;
  const target = current?.popover;
  const metrics = current?.metrics;
  if (!target || !metrics) {
    node.hidden = true;
    node.replaceChildren();
    popoverSignature = "";
    forgetFrames();
    return;
  }

  fillPopover(node, target);
  node.dataset.edge = current.settings.edge;
  // Rust sizes the card, because the hover zones are measured against the same numbers.
  if (metrics.popoverWidth) node.style.width = `${metrics.popoverWidth}px`;
  if (metrics.popoverHeight) node.style.maxHeight = `${metrics.popoverHeight}px`;
  node.style.left = node.style.right = node.style.top = node.style.bottom = "";

  const gap = metrics.popoverOffset ?? 10;
  const alongCentre = (start, length) => `${start + length / 2}px`;
  switch (current.settings.edge) {
    case "trailing":
      node.style.right = `${metrics.windowWidth - metrics.offsetX + gap}px`;
      node.style.top = alongCentre(metrics.offsetY, metrics.shapeHeight);
      node.style.transform = "translateY(-50%)";
      break;
    case "leading":
      node.style.left = `${metrics.offsetX + metrics.shapeWidth + gap}px`;
      node.style.top = alongCentre(metrics.offsetY, metrics.shapeHeight);
      node.style.transform = "translateY(-50%)";
      break;
    case "top":
      node.style.top = `${metrics.offsetY + metrics.shapeHeight + gap}px`;
      node.style.left = alongCentre(metrics.offsetX, metrics.shapeWidth);
      node.style.transform = "translateX(-50%)";
      break;
    default:
      node.style.bottom = `${metrics.windowHeight - metrics.offsetY + gap}px`;
      node.style.left = alongCentre(metrics.offsetX, metrics.shapeWidth);
      node.style.transform = "translateX(-50%)";
      break;
  }
  node.hidden = false;
}

/** The name a widget goes by, whichever kind it is. */
function widgetName(widgetId) {
  return (
    descriptors.find((one) => one.id === widgetId)?.name ??
    catalog.packages.find((pkg) => pkg.manifest.id === widgetId)?.manifest.name ??
    widgetId
  );
}

function fillPopover(node, target) {
  const revision =
    catalog.packages.find((pkg) => pkg.manifest.id === target.value)?.revision ?? 0;
  const signature = `${target.kind}:${target.value}:${revision}`;
  const changed = signature !== popoverSignature;
  // A reading is redrawn on every tick; a widget only when it is a different one,
  // unless it is a built-in whose view is nothing but numbers.
  if (!changed && target.kind === "widget" && !contentRefreshes(target.value)) return;
  popoverSignature = signature;

  if (target.kind === "chip") {
    node.innerHTML = chipContent(target.value, ambient);
  } else {
    node.replaceChildren(
      widgetContent(target.value, {
        ambient,
        cpuHistory,
        clipboard,
        prefs: slotPrefs(current.settings, target.value),
        name: widgetName,
        package: (id) => catalog.packages.find((pkg) => pkg.manifest.id === id),
        onReload: (id) => invoke("reload_widget", { widgetId: id }),
      }),
    );
  }
  forgetFrames();
}

function slotPrefs(settings, widgetId) {
  return settings.slots.find((slot) => slot.widgetId === widgetId)?.preferences ?? {};
}

// Opening and closing on hover is decided in Rust, which owns the window frame and
// can see the pointer even while the window resizes underneath it. These only carry
// the visual hover state.
function pointerEntered() {
  document.body.dataset.hover = "true";
}

function pointerLeft() {
  document.body.dataset.hover = "false";
}

// Drag the panel to slide it along its edge, or across the midpoint of the display to
// re-dock it. A press that never moves is a tap: it opens the panel when closed, and
// presses whatever Row is under it when open.
//
// The strip is draggable rather than a grab handle within it, because there is no
// chrome left to put one in — and a press that does not move never becomes a drag, so
// the two gestures do not compete.
function onMouseDown(event) {
  if (event.button !== 0) return;
  dragStart = { x: event.screenX, y: event.screenY, moved: false };
}

function onMouseMove(event) {
  if (!dragStart) return;
  const distance = Math.max(
    Math.abs(event.screenX - dragStart.x),
    Math.abs(event.screenY - dragStart.y),
  );
  if (!dragStart.moved && distance > 4) {
    dragStart.moved = true;
    dragging = true;
    panel.beginDrag();
  }
  if (dragging) panel.drag();
}

function onMouseUp(event) {
  if (!dragStart) return;
  const wasDrag = dragStart.moved;
  dragStart = null;
  if (wasDrag) {
    dragging = false;
    panel.endDrag();
    return;
  }
  if (!current) return;
  if (current.metrics.expanded) {
    pressRow(event.target.closest(".strip-row"));
  } else if (current.settings.activation !== "hotkeyOnly") {
    panel.open();
  }
}

/**
 * A press on a Row, as opposed to resting on one.
 *
 * Rust owns which Popover is showing, so this asks for one rather than drawing it —
 * drawing it here would last until the next poll, when the watchdog would replace it
 * with whatever it thinks the pointer is on.
 */
function pressRow(row) {
  if (!row) return;
  if (row.dataset.row === "settings") {
    invoke("open_settings");
    return;
  }
  const showing = current?.popover?.value === row.dataset.row;
  invoke("show_widget_popover", { widgetId: showing ? null : row.dataset.row });
}

function launch(path) {
  invoke("launch_app", { path });
  invoke("widget_invoke", { widgetId: "launcher", method: "ui.holdOpen", params: { value: false } });
  panel.close();
}

function wire() {
  document.addEventListener("mouseenter", pointerEntered);
  document.addEventListener("mouseleave", pointerLeft);
  document.addEventListener("mousedown", onMouseDown);
  document.addEventListener("mousemove", onMouseMove);
  document.addEventListener("mouseup", onMouseUp);
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") panel.close();
  });

  // A widget's view is only ever drawn in a popover now, so that is the one surface
  // its transport buttons, rows and search field are delegated from.
  wireWidgetSurface(document.getElementById("popover"));
}

function wireWidgetSurface(surface) {
  surface.addEventListener("click", (event) => {
    const transport = event.target.closest(".transport");
    if (transport) {
      invoke("widget_invoke", { widgetId: "media", method: transport.dataset.method, params: {} });
      return;
    }
    const launcherRow = event.target.closest(".launcher-row");
    if (launcherRow) {
      launch(launcherRow.dataset.path);
      return;
    }
    const clip = event.target.closest(".clip-row");
    if (clip) {
      const entry = clipboard.find((item) => item.id === clip.dataset.clipId);
      if (entry) {
        invoke("widget_invoke", {
          widgetId: "clipboard",
          method: "clipboard.write",
          params: { text: entry.text },
        });
        clip.classList.add("copied");
      }
    }
  });

  surface.addEventListener("input", async (event) => {
    if (event.target.id !== "launcher-input") return;
    const query = event.target.value;
    // Typing must keep the panel open even if the pointer has wandered off.
    invoke("widget_invoke", {
      widgetId: "launcher",
      method: "ui.holdOpen",
      params: { value: query.length > 0 },
    });
    launcherResults = query ? await invoke("search_apps", { query }) : [];
    launcherSelection = 0;
    const results = document.getElementById("launcher-results");
    if (results) builtin.renderLauncherResults(results, launcherResults, launcherSelection);
  });

  surface.addEventListener("keydown", (event) => {
    if (event.target.id !== "launcher-input") return;
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (!launcherResults.length) return;
      const delta = event.key === "ArrowDown" ? 1 : -1;
      launcherSelection =
        (launcherSelection + delta + launcherResults.length) % launcherResults.length;
      const results = document.getElementById("launcher-results");
      if (results) builtin.renderLauncherResults(results, launcherResults, launcherSelection);
    } else if (event.key === "Enter") {
      const app = launcherResults[launcherSelection];
      if (app) launch(app.path);
    }
  });
}

async function start() {
  await listen("panel-state", (event) => {
    current = event.payload;
    render();
  });
  await listen("metrics", (event) => {
    ambient = { ...ambient, metrics: event.payload };
    cpuHistory = [...cpuHistory.slice(1), event.payload.cpu ?? 0];
    render();
  });
  await listen("media", (event) => {
    ambient = { ...ambient, media: event.payload?.playing === false && !event.payload?.title ? null : event.payload };
    render();
  });
  await listen("clipboard", (event) => {
    clipboard = event.payload ?? [];
    ambient = { ...ambient, clipboardCount: clipboard.length };
    render();
  });
  await listen("widgets", (event) => {
    catalog = event.payload ?? { packages: [], failures: [] };
    // A reloaded widget's revision changed, so its popover has to be rebuilt.
    popoverSignature = "";
    render();
  });

  current = await panel.state();
  catalog = (await invoke("list_widgets")) ?? { packages: [], failures: [] };
  // Only for the names on the strip and its popovers; descriptors never change at runtime.
  descriptors = (await invoke("builtin_widgets")) ?? [];
  startBridgeRelay();
  render();
  wire();

  // The clock chip has no push source; a slow tick is cheaper than polling Rust.
  setInterval(() => {
    if (!current) return;
    // The clock has no push source; a slow tick is cheaper than polling Rust.
    if (current.metrics.expanded || current.metrics.showsContent) render();
  }, 5_000);
}

// A frontend error would otherwise leave an empty transparent window, which is
// indistinguishable from the panel simply not being there.
const report = (what, detail) => {
  try {
    invoke("log_frontend", { message: `${what}: ${detail}` });
  } catch {
    /* the bridge itself is gone; nothing useful left to do */
  }
};
window.addEventListener("error", (event) => report("error", event.message));
window.addEventListener("unhandledrejection", (event) => report("rejection", String(event.reason)));

start().catch((error) => report("start failed", String(error?.stack ?? error)));

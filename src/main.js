import { panel, listen, invoke } from "./lib/bridge.js";
import { renderShape } from "./lib/panel-view.js";
import { renderIdleHandle } from "./lib/idle-handle.js";

/** Latest state pushed from Rust. Rust owns the window; this owns what's drawn in it. */
let current = null;
/** Live values for the idle chips, refreshed only while something needs them. */
let ambient = { metrics: {}, media: null, clipboardCount: 0, widgetIcons: [] };

let openTimer = null;
let closeTimer = null;
let dragging = false;
let dragStart = null;
/// Guards against re-opening under a pointer that never left after an explicit close.
let hoverSuppressedUntil = 0;

const clearTimers = () => {
  clearTimeout(openTimer);
  clearTimeout(closeTimer);
  openTimer = null;
  closeTimer = null;
};

function render() {
  if (!current) return;
  const { metrics, settings } = current;
  renderShape(metrics, settings);

  const handle = document.getElementById("idle-handle");
  const body = document.getElementById("panel-body");

  if (metrics.expanded) {
    handle.hidden = true;
    body.hidden = false;
  } else {
    body.hidden = true;
    handle.hidden = !metrics.showsContent;
    if (metrics.showsContent) renderIdleHandle(handle, settings, ambient);
  }
}

// Pointer handling. The window is exactly the panel plus its margin, so entering and
// leaving the document is entering and leaving the panel.
function pointerEntered() {
  clearTimers();
  document.body.dataset.hover = "true";
  if (!current || current.metrics.expanded) return;
  if (Date.now() < hoverSuppressedUntil) return;
  if (current.settings.activation !== "hover") return;
  openTimer = setTimeout(() => panel.open(), current.settings.openDelay * 1000);
}

function pointerLeft() {
  clearTimers();
  document.body.dataset.hover = "false";
  if (!current || !current.metrics.expanded) return;
  if (current.settings.isPinned) return;
  closeTimer = setTimeout(() => panel.close(), current.settings.closeDelay * 1000);
}

// Drag the handle to slide the panel along its edge, or across the midpoint of the
// display to re-dock it. A press that never moves is a tap, which opens the panel.
function onMouseDown(event) {
  if (event.button !== 0) return;
  if (current?.metrics.expanded && !event.target.closest("#drag-grip")) return;
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
    clearTimers();
    panel.beginDrag();
  }
  if (dragging) panel.drag();
}

function onMouseUp() {
  if (!dragStart) return;
  const wasDrag = dragStart.moved;
  dragStart = null;
  if (wasDrag) {
    dragging = false;
    hoverSuppressedUntil = Date.now() + 300;
    panel.endDrag();
    return;
  }
  if (!current) return;
  if (!current.metrics.expanded && current.settings.activation !== "hotkeyOnly") {
    panel.open();
  }
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

  document.getElementById("close-button").addEventListener("click", () => {
    hoverSuppressedUntil = Date.now() + 450;
    panel.close();
  });

  document.getElementById("pin-button").addEventListener("click", () => {
    if (!current) return;
    const settings = { ...current.settings, isPinned: !current.settings.isPinned };
    panel.updateSettings(settings);
  });
}

async function start() {
  await listen("panel-state", (event) => {
    current = event.payload;
    render();
  });
  await listen("ambient", (event) => {
    ambient = { ...ambient, ...event.payload };
    if (current && !current.metrics.expanded) render();
  });

  current = await panel.state();
  render();
  wire();

  // The clock chip has no push source; a slow tick is cheaper than polling Rust.
  setInterval(() => {
    if (current && !current.metrics.expanded && current.metrics.showsContent) render();
  }, 10_000);
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

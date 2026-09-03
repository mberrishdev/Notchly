// Hosts custom widgets.
//
// Each widget runs in a sandboxed iframe under `widget://localhost/<id>/`. Without
// `allow-same-origin` the iframe gets an opaque origin, so it cannot reach the host
// page, another widget's storage, or the Tauri bridge directly. Everything it can do
// arrives through postMessage, which is checked here and forwarded to Rust.

import { invoke } from "./bridge.js";

const frames = new Map();

function widgetUrl(pkg) {
  const entry = pkg.manifest.entry || "index.html";
  return `widget://localhost/${encodeURIComponent(pkg.manifest.id)}/${entry}?rev=${pkg.revision}`;
}

/** Height the widget should get: its declared one, or what it measured, within bounds. */
function resolveHeight(manifest, measured) {
  const requested = manifest.height ?? measured ?? 0;
  const min = manifest.minHeight ?? 40;
  const max = manifest.maxHeight ?? 520;
  return Math.min(Math.max(requested === 0 ? 120 : requested, min), max);
}

export function createWidgetCard(pkg, { onReload }) {
  const card = document.createElement("section");
  card.className = "card";
  card.dataset.widgetId = pkg.manifest.id;

  // A custom widget draws its own content, so the shell adds no header around it. The
  // name still matters when a widget renders nothing and you need to know which one —
  // so it rides with the reload button, over the card, and only while it is hovered.
  const float = document.createElement("div");
  float.className = "card-float";
  float.innerHTML = `
    <span class="name">${escapeHtml(pkg.manifest.name)}</span>
    <button class="card-action" title="Reload">⟳</button>`;
  float.querySelector("button").addEventListener("click", () => onReload(pkg.manifest.id));

  const frame = document.createElement("iframe");
  // No allow-same-origin: the widget gets an opaque origin and no reach into the host.
  frame.setAttribute("sandbox", "allow-scripts");
  frame.setAttribute("scrolling", "no");
  frame.src = widgetUrl(pkg);
  frame.style.height = `${resolveHeight(pkg.manifest, null)}px`;

  card.append(frame, float);
  frames.set(frame, pkg.manifest.id);
  return card;
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c],
  );
}

/**
 * Relays one widget's bridge call. The widget id is taken from which iframe actually
 * sent the message, never from the message body — otherwise any widget could claim to
 * be another and borrow its permissions.
 */
export function startBridgeRelay() {
  window.addEventListener("message", async (event) => {
    const data = event.data;
    if (!data || data.__notchly !== true) return;

    let widgetId = null;
    for (const [frame, id] of frames) {
      if (frame.contentWindow === event.source) {
        widgetId = id;
        break;
      }
    }
    if (!widgetId) return;

    const reply = (payload) => event.source?.postMessage({ __notchlyReply: true, ...payload }, "*");

    if (data.method === "ui.resize") {
      applyHeight(widgetId, data.params?.height);
      reply({ id: data.id, result: true });
      return;
    }

    try {
      const result = await invoke("widget_invoke", {
        widgetId,
        method: data.method,
        params: data.params ?? {},
      });
      reply({ id: data.id, result });
    } catch (error) {
      reply({ id: data.id, error: String(error?.message ?? error) });
    }
  });
}

function applyHeight(widgetId, height) {
  if (!Number.isFinite(height)) return;
  for (const [frame, id] of frames) {
    if (id !== widgetId) continue;
    const manifest = frame.__manifest ?? {};
    if (manifest.height != null) return; // a fixed height wins over self-measurement
    frame.style.height = `${resolveHeight(manifest, height)}px`;
  }
}

export function trackManifest(card, manifest) {
  const frame = card.querySelector("iframe");
  if (frame) frame.__manifest = manifest;
}

/**
 * Drops the bookkeeping for iframes that are no longer on the page.
 *
 * Scoped to the document rather than to one container: a widget's iframe can be in the
 * stack or in a popover card, and a sweep that only knew about one of those would forget
 * a live frame in the other — and a forgotten frame's bridge calls stop being
 * attributable, so they are refused.
 */
export function forgetFrames() {
  for (const frame of Array.from(frames.keys())) {
    if (!frame.isConnected) frames.delete(frame);
  }
}

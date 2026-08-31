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

  const header = document.createElement("header");
  header.className = "card-header";
  header.innerHTML = `
    <span class="card-title">${escapeHtml(pkg.manifest.name)}</span>
    <span class="card-spacer"></span>
    <button class="card-action" title="Reload">⟳</button>`;
  header.querySelector("button").addEventListener("click", () => onReload(pkg.manifest.id));

  const frame = document.createElement("iframe");
  // No allow-same-origin: the widget gets an opaque origin and no reach into the host.
  frame.setAttribute("sandbox", "allow-scripts");
  frame.setAttribute("scrolling", "no");
  frame.src = widgetUrl(pkg);
  frame.style.height = `${resolveHeight(pkg.manifest, null)}px`;

  card.append(header, frame);
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

export function forgetFrames(container) {
  for (const frame of Array.from(frames.keys())) {
    if (!container.contains(frame)) frames.delete(frame);
  }
}

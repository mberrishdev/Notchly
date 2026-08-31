import { notchPath, growsHorizontally } from "./notch-shape.js";

// Draws the panel outline and animates it between states.
//
// The shape is interpolated frame by frame rather than transitioned in CSS: an SVG
// `d` attribute doesn't animate reliably across engines, and driving it here keeps the
// open and close curves under our control. Rust sizes the *window* before the open
// animation and shrinks it after the close one, so this only ever animates inside a
// window that is already big enough.

const MATERIAL_OPACITY = { glass: 0.84, tinted: 0.93, solid: 0.99 };
const OPEN_MS = 300;
const CLOSE_MS = 260;

let drawn = null;
let frame = null;

const lerp = (from, to, t) => from + (to - from) * t;
const easeOut = (t) => 1 - Math.pow(1 - t, 3);
const easeIn = (t) => t * t * t;

function paint(metrics, settings, contentOpacity) {
  const { shapeWidth, shapeHeight, cornerRadius, inverseRadius, offsetX, offsetY } = metrics;
  const path = notchPath(settings.edge, shapeWidth, shapeHeight, cornerRadius, inverseRadius);
  const transform = `translate(${offsetX} ${offsetY})`;

  for (const id of ["shape", "hairline", "clip-path"]) {
    const node = document.getElementById(id);
    node.setAttribute("d", path);
    node.setAttribute("transform", transform);
  }

  document.getElementById("shape").style.fillOpacity =
    (MATERIAL_OPACITY[settings.material] ?? 0.96) * settings.opacity;

  const content = document.getElementById("content");
  content.style.left = `${offsetX}px`;
  content.style.top = `${offsetY}px`;
  content.style.width = `${shapeWidth}px`;
  content.style.height = `${shapeHeight}px`;
  content.style.opacity = String(contentOpacity);

  // Keep content clear of the concave flares at either end of the panel.
  const pad = Math.max(inverseRadius, 6);
  content.style.padding = growsHorizontally(settings.edge) ? `${pad}px 0` : `0 ${pad}px`;

  document.documentElement.style.setProperty("--accent", settings.accentHex);
  document.body.dataset.edge = settings.edge;
}

function interpolate(from, to, t) {
  return {
    shapeWidth: lerp(from.shapeWidth, to.shapeWidth, t),
    shapeHeight: lerp(from.shapeHeight, to.shapeHeight, t),
    cornerRadius: lerp(from.cornerRadius, to.cornerRadius, t),
    inverseRadius: lerp(from.inverseRadius, to.inverseRadius, t),
    offsetX: lerp(from.offsetX, to.offsetX, t),
    offsetY: lerp(from.offsetY, to.offsetY, t),
  };
}

let lastSettings = null;

/**
 * Draws `metrics`, animating from whatever is currently on screen.
 *
 * `contentSwap` runs once the outgoing content has faded, so the panel body and the
 * idle handle never overlap mid-transition.
 */
export function renderShape(metrics, settings, contentSwap) {
  lastSettings = settings;
  const target = { ...metrics };
  const previous = drawn;
  drawn = target;

  if (frame) cancelAnimationFrame(frame);

  const sameShape =
    previous &&
    Math.abs(previous.shapeWidth - target.shapeWidth) < 0.5 &&
    Math.abs(previous.shapeHeight - target.shapeHeight) < 0.5;

  if (!previous || sameShape || settings.reduceMotion) {
    contentSwap?.();
    paint(target, settings, 1);
    return;
  }

  const opening = target.expanded;
  const duration = opening ? OPEN_MS : CLOSE_MS;
  const ease = opening ? easeOut : easeIn;
  const start = performance.now();
  let swapped = false;

  // Fade the old content out early, the new content in late, so the swap lands while
  // the panel is at its least readable rather than mid-stride.
  const contentFade = (t) => (opening ? Math.max(0, (t - 0.45) / 0.55) : Math.max(0, 1 - t / 0.4));

  const step = (now) => {
    const t = Math.min(1, (now - start) / duration);
    const eased = ease(t);
    if (!swapped && (opening ? t >= 0.45 : t >= 0.4)) {
      swapped = true;
      contentSwap?.();
    }
    paint(interpolate(previous, target, eased), settings, contentFade(t));
    if (t < 1) {
      frame = requestAnimationFrame(step);
    } else {
      frame = null;
      if (!swapped) contentSwap?.();
      paint(target, settings, 1);
    }
  };
  frame = requestAnimationFrame(step);
}

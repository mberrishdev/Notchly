import { notchPath, growsHorizontally } from "./notch-shape.js";

// Draws the panel outline and animates it between states.
//
// The shape is interpolated frame by frame rather than transitioned in CSS: an SVG
// `d` attribute doesn't animate reliably across engines, and driving it here keeps the
// open and close curves under our control. Rust sizes the *window* before the open
// animation and shrinks it after the close one, so this only ever animates inside a
// window that is already big enough.

// A shaped window can't sit on a real blur (see docs/PORTING.md), so "glass" is a
// translucent fill. Kept close to opaque: the notch this imitates is solid, and at
// lower values it reads as a rendering fault rather than as depth.
// Long enough for the spring to settle: cutting it at 440ms leaves a 1.8pt snap on
// the final frame, at 520ms it is 0.16pt.
const OPEN_MS = 520;
const CLOSE_MS = 260;

let drawn = null;
let frame = null;

const lerp = (from, to, t) => from + (to - from) * t;

/**
 * A damped spring, matching the curve the Swift build used (response 0.38, damping
 * 0.78). The slight overshoot is what makes opening feel like a physical thing rather
 * than a size change — an ease-out reads as mechanical at this size.
 */
function spring(t) {
  if (t >= 1) return 1;
  const omega = (2 * Math.PI) / 0.38;
  const zeta = 0.78;
  const damped = omega * Math.sqrt(1 - zeta * zeta);
  const decay = Math.exp(-zeta * omega * t);
  return 1 - decay * (Math.cos(damped * t) + ((zeta * omega) / damped) * Math.sin(damped * t));
}

const easeIn = (t) => t * t * t;

/**
 * Where the shape sits inside the window: hugging the docked edge, centred across it.
 *
 * Recomputed every frame from the animated size rather than taken from the metrics,
 * because the window is already at its target size while the shape is still at its
 * old one. Using the old offsets put the collapsed shape at the top of the open
 * window on the first frame, which is what made the panel appear to jump upward.
 */
function offsetsIn(edge, shapeWidth, shapeHeight, windowWidth, windowHeight) {
  switch (edge) {
    case "leading":
      return { offsetX: 0, offsetY: (windowHeight - shapeHeight) / 2 };
    case "trailing":
      return { offsetX: windowWidth - shapeWidth, offsetY: (windowHeight - shapeHeight) / 2 };
    case "top":
      return { offsetX: (windowWidth - shapeWidth) / 2, offsetY: 0 };
    default:
      return { offsetX: (windowWidth - shapeWidth) / 2, offsetY: windowHeight - shapeHeight };
  }
}

function paint(metrics, settings, contentOpacity) {
  const { shapeWidth, shapeHeight, cornerRadius, inverseRadius } = metrics;
  const { offsetX, offsetY } = offsetsIn(
    settings.edge,
    shapeWidth,
    shapeHeight,
    metrics.windowWidth,
    metrics.windowHeight,
  );
  const path = notchPath(settings.edge, shapeWidth, shapeHeight, cornerRadius, inverseRadius);
  const transform = `translate(${offsetX} ${offsetY})`;

  for (const id of ["shape", "hairline", "clip-path"]) {
    const node = document.getElementById(id);
    node.setAttribute("d", path);
    node.setAttribute("transform", transform);
  }

  document.getElementById("shape").style.fillOpacity = settings.opacity;

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
    // The window is already at its target size for the whole animation.
    windowWidth: to.windowWidth,
    windowHeight: to.windowHeight,
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
  const ease = opening ? spring : easeIn;
  const start = performance.now();
  let swapped = false;

  // Fade the old content out early, the new content in late, so the swap lands while
  // the panel is at its least readable rather than mid-stride.
  const contentFade = (t) =>
    opening ? Math.min(1, Math.max(0, (t - 0.22) / 0.4)) : Math.max(0, 1 - t / 0.4);

  const step = (now) => {
    const t = Math.min(1, (now - start) / duration);
    const eased = ease(t);
    if (!swapped && (opening ? t >= 0.22 : t >= 0.4)) {
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

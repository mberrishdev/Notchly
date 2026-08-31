import { notchPath, growsHorizontally } from "./notch-shape.js";

// Draws the panel outline and positions everything inside it.
//
// The window is always slightly larger than the shape — the extra room is where the
// shadow falls — so the shape is offset rather than filling the window.

// A shaped, transparent window can't sit on an NSVisualEffectView without the blur
// showing as a rectangle behind the concave corners, so "glass" is a translucent fill
// rather than true vibrancy. See docs/PORTING.md.
const MATERIAL_OPACITY = { glass: 0.84, tinted: 0.93, solid: 0.99 };

export function renderShape(metrics, settings) {
  const { shapeWidth, shapeHeight, cornerRadius, inverseRadius, offsetX, offsetY } = metrics;
  const path = notchPath(settings.edge, shapeWidth, shapeHeight, cornerRadius, inverseRadius);
  const transform = `translate(${offsetX} ${offsetY})`;

  for (const id of ["shape", "hairline", "clip-path"]) {
    const node = document.getElementById(id);
    node.setAttribute("d", path);
    node.setAttribute("transform", transform);
  }

  const shape = document.getElementById("shape");
  shape.style.fillOpacity = (MATERIAL_OPACITY[settings.material] ?? 0.96) * settings.opacity;

  const content = document.getElementById("content");
  content.style.left = `${offsetX}px`;
  content.style.top = `${offsetY}px`;
  content.style.width = `${shapeWidth}px`;
  content.style.height = `${shapeHeight}px`;

  // Keep content clear of the concave flares at either end of the panel.
  const pad = Math.max(inverseRadius, 6);
  content.style.padding = growsHorizontally(settings.edge) ? `${pad}px 0` : `0 ${pad}px`;

  document.documentElement.style.setProperty("--accent", settings.accentHex);
  document.body.dataset.edge = settings.edge;
  document.body.dataset.expanded = String(metrics.expanded);
  document.body.dataset.showsContent = String(metrics.showsContent);
}

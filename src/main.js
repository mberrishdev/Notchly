import { notchPath, growsHorizontally } from "./lib/notch-shape.js";

const EDGE = "trailing";
const CORNER_RADIUS = 26;
const INVERSE_RADIUS = 14;

// The real panel reserves room around the shape for its shadow; the spike keeps that
// margin so there is genuinely empty window area to test transparency against.
const SHADOW_MARGIN = 40;

function render() {
  const width = window.innerWidth;
  const height = window.innerHeight;
  const shapeWidth = width - SHADOW_MARGIN;
  const path = notchPath(EDGE, shapeWidth, height, CORNER_RADIUS, INVERSE_RADIUS);

  for (const id of ["shape", "hairline", "clip-path"]) {
    const node = document.getElementById(id);
    node.setAttribute("d", path);
    node.setAttribute("transform", `translate(${SHADOW_MARGIN} 0)`);
  }

  // Keep content clear of the concave flares at either end.
  const pad = Math.max(INVERSE_RADIUS, 6);
  const content = document.getElementById("content");
  content.style.left = `${SHADOW_MARGIN}px`;
  content.style.padding = growsHorizontally(EDGE)
    ? `${pad}px 16px`
    : `14px ${pad}px`;
}

render();
window.addEventListener("resize", render);

// Ask the Rust side what the native window actually looks like after configuration.
async function report() {
  const target = document.getElementById("report");
  try {
    const result = await window.__TAURI__.core.invoke("window_report");
    target.textContent = JSON.stringify(result, null, 1);
  } catch (error) {
    target.textContent = `invoke failed: ${error}`;
  }
}
report();

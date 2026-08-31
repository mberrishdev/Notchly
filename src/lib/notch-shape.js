// The Panel outline, ported from the Swift `NotchShape`.
//
// Two of its corners are concave: they flare outward where the panel meets the screen
// edge, which is what makes the shape read as part of the bezel instead of a window
// floating on top of it. The geometry is authored once for a top-docked panel and then
// transformed for the other three edges, so all four sides stay identical.

/** @typedef {"top" | "bottom" | "leading" | "trailing"} ScreenEdge */

/** True on the left and right edges, where the panel extends horizontally. */
export function growsHorizontally(edge) {
  return edge === "leading" || edge === "trailing";
}

const clamp = (value, min, max) => Math.max(min, Math.min(value, max));

/**
 * Builds the canonical top-docked outline: concave flares at y = 0, rounded corners at
 * the bottom. Returned as a list of path commands in canonical space.
 */
function canonicalPath(width, height, cornerRadius, inverseRadius) {
  const ir = clamp(inverseRadius, 0, Math.min(width / 2, height));
  const cr = clamp(cornerRadius, 0, Math.min((width - 2 * ir) / 2, height - ir));

  return [
    ["M", 0, 0],
    ["Q", ir, 0, ir, ir],
    ["L", ir, height - cr],
    ["Q", ir, height, ir + cr, height],
    ["L", width - ir - cr, height],
    ["Q", width - ir, height, width - ir, height - cr],
    ["L", width - ir, ir],
    ["Q", width - ir, 0, width, 0],
    ["Z"],
  ];
}

/** Maps canonical (top-docked) coordinates onto the requested edge. */
function transformFor(edge, width, height) {
  switch (edge) {
    case "top":
      return (x, y) => [x, y];
    case "bottom":
      return (x, y) => [x, height - y];
    case "trailing":
      return (x, y) => [width - y, x];
    case "leading":
      return (x, y) => [y, x];
    default:
      throw new Error(`unknown edge: ${edge}`);
  }
}

/**
 * SVG path data for the panel outline.
 *
 * @param {ScreenEdge} edge which side of the display the panel docks to
 * @param {number} width  drawing width, including the flares
 * @param {number} height drawing height, including the flares
 */
export function notchPath(edge, width, height, cornerRadius, inverseRadius) {
  if (width <= 0 || height <= 0) return "";

  // On the side edges the canonical rect is the transposed one.
  const [cw, ch] = growsHorizontally(edge) ? [height, width] : [width, height];
  const commands = canonicalPath(cw, ch, cornerRadius, inverseRadius);
  const map = transformFor(edge, width, height);
  const round = (n) => Math.round(n * 1000) / 1000;

  return commands
    .map((command) => {
      const [op, ...values] = command;
      if (op === "Z") return "Z";
      const points = [];
      for (let i = 0; i < values.length; i += 2) {
        const [x, y] = map(values[i], values[i + 1]);
        points.push(`${round(x)} ${round(y)}`);
      }
      return `${op}${points.join(" ")}`;
    })
    .join("");
}

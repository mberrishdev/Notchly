// Notchly's hero, drawn with the app's own geometry.
//
// Deliberately one classic script rather than ES modules: a landing page has to work
// when someone double-clicks index.html, and browsers refuse module imports over
// file://. Nothing here needs a bundler or a server.
(function () {

const clamp = (value, min, max) => Math.max(min, Math.min(value, max));

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

function transformFor(edge, width, height) {
  switch (edge) {
    case "top": return (x, y) => [x, y];
    case "bottom": return (x, y) => [x, height - y];
    case "trailing": return (x, y) => [width - y, x];
    case "leading": return (x, y) => [y, x];
    default: throw new Error(`unknown edge: ${edge}`);
  }
}

const growsHorizontally = (edge) => edge === "leading" || edge === "trailing";

function notchPath(edge, width, height, cornerRadius, inverseRadius) {
  if (width <= 0 || height <= 0) return "";
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

/** An arc reading, drawn the way the handle draws it. */
function ring(iconPath, fraction, tone, size = 34) {
  const stroke = Math.max(2, size * 0.08);
  const radius = (size - stroke) / 2;
  const circumference = 2 * Math.PI * radius;
  const filled = circumference * clamp(fraction, 0, 1);
  const mid = size / 2;
  const glyph = Math.round(size * 0.5);
  return `<span class="ring" style="width:${size}px;height:${size}px">
    <svg viewBox="0 0 ${size} ${size}" width="${size}" height="${size}" aria-hidden="true">
      <circle cx="${mid}" cy="${mid}" r="${radius}" fill="none" stroke="rgba(255,255,255,.12)" stroke-width="${stroke}"/>
      <circle cx="${mid}" cy="${mid}" r="${radius}" fill="none" stroke="var(--tone-${tone})" stroke-width="${stroke}"
              stroke-linecap="round" transform="rotate(-90 ${mid} ${mid})"
              stroke-dasharray="${filled.toFixed(2)} ${(circumference - filled).toFixed(2)}"/>
    </svg>
    <svg class="ring-glyph" viewBox="0 0 16 16" width="${glyph}" height="${glyph}" aria-hidden="true">${iconPath}</svg>
  </span>`;
}

const glyphs = {
  cpu: `<rect x="4.5" y="4.5" width="7" height="7" rx="1.4" fill="none" stroke="currentColor" stroke-width="1.3"/>
    <rect x="6.75" y="6.75" width="2.5" height="2.5" rx=".6" fill="currentColor"/>
    <g stroke="currentColor" stroke-width="1.2" stroke-linecap="round">
      <path d="M6.5 2.6v1.6M9.5 2.6v1.6M6.5 11.8v1.6M9.5 11.8v1.6"/>
      <path d="M2.6 6.5h1.6M2.6 9.5h1.6M11.8 6.5h1.6M11.8 9.5h1.6"/></g>`,
  memory: `<rect x="2.5" y="4.5" width="11" height="7" rx="1.2" fill="none" stroke="currentColor" stroke-width="1.3"/>
    <g stroke="currentColor" stroke-width="1.2" stroke-linecap="round">
      <path d="M5.5 6.8v2.4M8 6.8v2.4M10.5 6.8v2.4"/><path d="M4.6 11.5v1.4M11.4 11.5v1.4"/></g>`,
  battery: `<rect x="1.8" y="5" width="11" height="6" rx="1.8" fill="none" stroke="currentColor" stroke-width="1.3"/>
    <path d="M14.2 7v2" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
    <rect x="3.4" y="6.6" width="5" height="2.8" rx=".8" fill="currentColor"/>`,
};


const stage = document.getElementById("stage");
const toggle = document.getElementById("toggle");

let edge = "leading";
let open = false;

// Real proportions, scaled to the frame: the panel is 372 x 540 with a 26pt corner and
// a 14pt flare; the handle is 44 deep with a 9pt flare.
const PANEL = { depth: 258, extent: 336, corner: 26, flare: 14 };
const HANDLE = { depth: 52, extent: 292, corner: 13, flare: 9 };

const handleBody = `
  <div class="strip">
    ${ring(glyphs.cpu, 0.34, "normal", 30)}<span class="read">34%</span>
    ${ring(glyphs.memory, 0.68, "caution", 30)}<span class="read">68%</span>
    ${ring(glyphs.battery, 0.91, "good", 30)}<span class="read">91%</span>
    <span class="rule"></span>
    <span class="read time">14:32</span>
  </div>`;

const panelBody = `
  <div class="panel-body">
    <span class="grab"></span>
    <div class="card clock">
      <span class="time-lg">14:32</span>
      <span class="sub">Tuesday 2 September</span>
    </div>
    <div class="card media">
      <span class="art"></span>
      <span class="meta"><b>Weightless</b><i>Marconi Union</i></span>
    </div>
    <div class="card stats">
      ${ring(glyphs.cpu, 0.34, "normal", 46)}
      ${ring(glyphs.memory, 0.68, "caution", 46)}
      ${ring(glyphs.battery, 0.91, "good", 46)}
    </div>
  </div>`;

function draw() {
  const shape = open ? PANEL : HANDLE;
  const horizontal = growsHorizontally(edge);
  const width = horizontal ? shape.depth : shape.extent;
  const height = horizontal ? shape.extent : shape.depth;
  const path = notchPath(edge, width, height, shape.corner, shape.flare);

  stage.dataset.edge = edge;
  stage.dataset.open = String(open);
  stage.style.width = `${width}px`;
  stage.style.height = `${height}px`;
  stage.innerHTML = `
    <svg class="shape" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" aria-hidden="true">
      <path d="${path}"/>
    </svg>
    <div class="content">${open ? panelBody : handleBody}</div>`;

  // Restart the one piece of motion on the page: the panel arriving at its new edge.
  stage.classList.remove("settling");
  void stage.offsetWidth;
  stage.classList.add("settling");
}

for (const button of document.querySelectorAll("[data-edge]")) {
  button.addEventListener("click", () => {
    edge = button.dataset.edge;
    for (const other of document.querySelectorAll("[data-edge]")) {
      other.setAttribute("aria-pressed", String(other === button));
    }
    draw();
  });
}

toggle.addEventListener("click", () => {
  open = !open;
  toggle.textContent = open ? "Close it" : "Open it";
  draw();
});

draw();

// The star count, if GitHub is reachable and has an answer worth showing. Anything
// else — offline, rate limited, a repo with no stars yet — leaves the button reading
// "Star", which is the call to action anyway.
fetch("https://api.github.com/repos/mberrishdev/Notchly")
  .then((response) => (response.ok ? response.json() : null))
  .then((repo) => {
    const count = repo && repo.stargazers_count;
    if (!count) return;
    const node = document.getElementById("stars");
    node.textContent = count >= 1000 ? `${(count / 1000).toFixed(1)}k` : String(count);
    node.hidden = false;
  })
  .catch(() => {});

})();

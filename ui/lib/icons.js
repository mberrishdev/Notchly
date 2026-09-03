// Inline SVG glyphs for the idle handle.
//
// These were Unicode characters first — ◉ ▤ ❐ ▮ — which rendered inconsistently and,
// in the clipboard's case, as a missing-glyph box. Drawing them keeps every chip
// crisp at 10px and independent of what the system font happens to contain.

const svg = (body, size = 11) =>
  `<svg class="glyph-svg" viewBox="0 0 16 16" width="${size}" height="${size}" aria-hidden="true">${body}</svg>`;

export const icons = {
  cpu: svg(`
    <rect x="4.5" y="4.5" width="7" height="7" rx="1.4" fill="none" stroke="currentColor" stroke-width="1.3"/>
    <rect x="6.75" y="6.75" width="2.5" height="2.5" rx="0.6" fill="currentColor"/>
    <g stroke="currentColor" stroke-width="1.2" stroke-linecap="round">
      <path d="M6.5 2.6v1.6M9.5 2.6v1.6M6.5 11.8v1.6M9.5 11.8v1.6"/>
      <path d="M2.6 6.5h1.6M2.6 9.5h1.6M11.8 6.5h1.6M11.8 9.5h1.6"/>
    </g>`),

  memory: svg(`
    <rect x="2.5" y="4.5" width="11" height="7" rx="1.2" fill="none" stroke="currentColor" stroke-width="1.3"/>
    <g stroke="currentColor" stroke-width="1.2" stroke-linecap="round">
      <path d="M5.5 6.8v2.4M8 6.8v2.4M10.5 6.8v2.4"/>
      <path d="M4.6 11.5v1.4M11.4 11.5v1.4"/>
    </g>`),

  battery: svg(`
    <rect x="1.8" y="5" width="11" height="6" rx="1.8" fill="none" stroke="currentColor" stroke-width="1.3"/>
    <path d="M14.2 7v2" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
    <rect x="3.4" y="6.6" width="5" height="2.8" rx="0.8" fill="currentColor"/>`),

  charging: svg(`
    <path d="M8.6 1.5 3.4 9h3.4l-1.4 5.5L12.6 7H9.2z" fill="currentColor"/>`),

  power: svg(`
    <path d="M8 2.6v5" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
    <path d="M4.6 4.9a4.6 4.6 0 1 0 6.8 0" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>`),

  clipboard: svg(`
    <rect x="3.5" y="3" width="9" height="11" rx="1.6" fill="none" stroke="currentColor" stroke-width="1.3"/>
    <rect x="6" y="1.6" width="4" height="2.8" rx="1" fill="currentColor"/>`),

  widget: svg(`
    <g fill="currentColor">
      <rect x="2.6" y="2.6" width="4.6" height="4.6" rx="1.1"/>
      <rect x="8.8" y="2.6" width="4.6" height="4.6" rx="1.1"/>
      <rect x="2.6" y="8.8" width="4.6" height="4.6" rx="1.1"/>
      <rect x="8.8" y="8.8" width="4.6" height="4.6" rx="1.1"/>
    </g>`),

  clock: svg(`
    <circle cx="8" cy="8" r="5.6" fill="none" stroke="currentColor" stroke-width="1.3"/>
    <path d="M8 4.8V8l2.4 1.6" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>`),

  search: svg(`
    <circle cx="7.2" cy="7.2" r="4.4" fill="none" stroke="currentColor" stroke-width="1.4"/>
    <path d="M10.6 10.6 13.6 13.6" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>`),

  // Sliders rather than a cog: at 15px a cog's teeth close up into a disc, and the
  // radial version of this read as a brightness sun.
  settings: svg(`
    <g stroke="currentColor" stroke-width="1.4" stroke-linecap="round">
      <path d="M2.4 4.4h11.2M2.4 8h11.2M2.4 11.6h11.2"/>
    </g>
    <g fill="var(--shell, #0b0c0f)" stroke="currentColor" stroke-width="1.4">
      <circle cx="10.4" cy="4.4" r="1.7"/>
      <circle cx="5.6" cy="8" r="1.7"/>
      <circle cx="9.6" cy="11.6" r="1.7"/>
    </g>`),

  note: svg(`
    <path d="M6.2 11.4V3.6l6.2-1.5v7.6" fill="none" stroke="currentColor" stroke-width="1.4"
          stroke-linecap="round" stroke-linejoin="round"/>
    <circle cx="4.4" cy="11.6" r="1.9" fill="currentColor"/>
    <circle cx="10.6" cy="9.9" r="1.9" fill="currentColor"/>`),

};

/**
 * The glyph that stands for a widget wherever one is shown by icon alone — the idle
 * handle's widget-icons chip, and the compact Icon Strip. One map, so a widget cannot
 * be one picture in the handle and another on the strip.
 */
const WIDGET_GLYPHS = {
  clock: icons.clock,
  media: icons.note,
  system: icons.cpu,
  launcher: icons.search,
  clipboard: icons.clipboard,
};

/** Custom widgets have no symbol of their own, so they all get the generic mark. */
export const widgetGlyph = (widgetId) => WIDGET_GLYPHS[widgetId] ?? icons.widget;

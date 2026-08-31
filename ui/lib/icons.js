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

  calendar: svg(`
    <rect x="2.6" y="3.6" width="10.8" height="10" rx="1.6" fill="none" stroke="currentColor" stroke-width="1.3"/>
    <path d="M2.6 6.8h10.8M5.6 2.2v2.6M10.4 2.2v2.6" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>`),
};

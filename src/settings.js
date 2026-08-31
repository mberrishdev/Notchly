// The settings window.
//
// Every pane edits one shared Settings object and pushes the whole thing back to Rust,
// which persists it and re-lays out the panel. That keeps a single write path — the
// menu bar, the panel, and this window all go through `update_settings`.

import { invoke, listen } from "./lib/bridge.js";
import { notchPath, growsHorizontally } from "./lib/notch-shape.js";
import { widgetsPane, customPane, aboutPane } from "./lib/settings-widgets.js";
import {
  el, field, toggle, slider, segmented, select, button, group,
} from "./lib/settings-controls.js";

let settings = null;
let catalog = { packages: [], failures: [] };
let builtins = [];
let displays = [];
let expandedRow = null;
let activeTab = "general";

/**
 * Pushes the whole settings object back to Rust, which persists it and re-lays out the
 * panel. One write path: the menu bar, the panel and this window all go through it.
 */
async function commit(mutate) {
  mutate(settings);
  await invoke("update_settings", { settings });
  render();
}

// Panes

function generalPane() {
  const nodes = [];

  nodes.push(
    group("Placement", [
      field(
        "Dock to",
        null,
        segmented(
          [["top", "Top"], ["bottom", "Bottom"], ["leading", "Left"], ["trailing", "Right"]],
          settings.edge,
          (edge) => commit((s) => (s.edge = edge)),
        ),
      ),
      field(
        "Position along edge",
        growsHorizontally(settings.edge) ? "0% is the top of the display." : "0% is the left of the display.",
        slider(settings.alignment * 100, 0, 100, 1, "%", (v) => commit((s) => (s.alignment = v / 100))),
      ),
      field(
        "Display",
        "Follow the pointer, or pin the panel to one screen.",
        select(
          [["", "Screen with pointer"], ...displays.map((name) => [name, name])],
          settings.preferredScreen ?? "",
          (name) => commit((s) => (s.preferredScreen = name || null)),
        ),
      ),
      field(
        "Edge offset",
        "Nudges the panel away from the screen edge.",
        slider(settings.edgeInset, 0, 40, 1, "pt", (v) => commit((s) => (s.edgeInset = v))),
      ),
    ]),
  );

  const activationHelp = {
    hover: "Opens when the pointer rests on the handle.",
    click: "Opens on click, so the handle never opens by accident.",
    hotkeyOnly: "Stays closed until the keyboard shortcut fires.",
  }[settings.activation];

  nodes.push(
    group("Opening", [
      field(
        "Activation",
        activationHelp,
        select(
          [["hover", "Hover"], ["click", "Click"], ["hotkeyOnly", "Hotkey only"]],
          settings.activation,
          (mode) => commit((s) => (s.activation = mode)),
        ),
      ),
      settings.activation === "hover"
        ? field("Open delay", null, slider(settings.openDelay * 1000, 0, 800, 10, "ms", (v) =>
            commit((s) => (s.openDelay = v / 1000))))
        : null,
      field(
        "Close delay",
        "How long the panel waits after the pointer leaves.",
        slider(settings.closeDelay * 1000, 0, 2000, 20, "ms", (v) => commit((s) => (s.closeDelay = v / 1000))),
      ),
      field("Close when clicking outside", null, toggle(settings.closeOnOutsideClick, (v) =>
        commit((s) => (s.closeOnOutsideClick = v)))),
      field("Keep the panel open", null, toggle(settings.isPinned, (v) => commit((s) => (s.isPinned = v)))),
    ]),
  );

  nodes.push(
    group("Shortcut", [
      field("Toggle panel", "Works everywhere, no Accessibility access needed.", hotkeyRecorder()),
    ]),
  );

  nodes.push(
    group("System", [
      field("Launch at login", null, toggle(settings.launchAtLogin, (v) =>
        commit((s) => (s.launchAtLogin = v)))),
      field("Show menu bar icon", null, toggle(settings.showsMenuBarIcon, (v) =>
        commit((s) => (s.showsMenuBarIcon = v)))),
      field(
        "Clipboard history",
        "Older unpinned entries are dropped once the limit is hit.",
        slider(settings.clipboardHistoryLimit, 20, 500, 10, "", (v) =>
          commit((s) => (s.clipboardHistoryLimit = v))),
      ),
    ]),
  );

  return nodes;
}

/** Click, then press the combination you want. Escape cancels. */
function hotkeyRecorder() {
  const display = el("button", "action", settings.hotkey.accelerator || "None");
  let recording = false;

  const stop = () => {
    recording = false;
    display.textContent = settings.hotkey.accelerator || "None";
    window.removeEventListener("keydown", onKey, true);
  };

  const onKey = (event) => {
    event.preventDefault();
    event.stopPropagation();
    if (event.key === "Escape") return stop();
    const parts = [];
    if (event.ctrlKey) parts.push("Ctrl");
    if (event.altKey) parts.push("Alt");
    if (event.shiftKey) parts.push("Shift");
    if (event.metaKey) parts.push("Cmd");
    const key = event.key.length === 1 ? event.key.toUpperCase() : event.key;
    if (["Control", "Alt", "Shift", "Meta"].includes(event.key)) return;
    // A bare key would fire constantly; require at least one modifier.
    if (!parts.length) return;
    parts.push(key);
    stop();
    commit((s) => (s.hotkey = { accelerator: parts.join("+"), isEnabled: true }));
  };

  display.addEventListener("click", () => {
    if (recording) return stop();
    recording = true;
    display.textContent = "Press keys…";
    window.addEventListener("keydown", onKey, true);
  });

  return [
    display,
    button("Clear", () => commit((s) => (s.hotkey = { accelerator: "", isEnabled: false }))),
  ];
}

function appearancePane() {
  const nodes = [group("Preview", [preview()])];

  nodes.push(
    group("Surface", [
      field(
        "Material",
        null,
        segmented(
          [["glass", "Glass"], ["tinted", "Tinted"], ["solid", "Solid"]],
          settings.material,
          (material) => commit((s) => (s.material = material)),
        ),
      ),
      field("Opacity", null, slider(settings.opacity * 100, 40, 100, 1, "%", (v) =>
        commit((s) => (s.opacity = v / 100)))),
      field("Accent", null, accentPicker()),
    ], "A shaped window can't sit on a real blur without it showing as a rectangle behind the concave corners, so Glass is a translucent fill rather than vibrancy."),
  );

  nodes.push(
    group("Shape", [
      field("Panel width", null, slider(settings.panelWidth, 240, 560, 1, "pt", (v) =>
        commit((s) => (s.panelWidth = v)))),
      field("Panel height", null, slider(settings.panelHeight, 200, 900, 1, "pt", (v) =>
        commit((s) => (s.panelHeight = v)))),
      field("Corner radius", null, slider(settings.cornerRadius, 0, 44, 1, "pt", (v) =>
        commit((s) => (s.cornerRadius = v)))),
    ], "Width and height describe how far the panel reaches from its edge and how long it runs along it."),
  );

  nodes.push(idleHandleGroup());
  nodes.push(
    group("Motion", [
      field("Show the handle when idle", null, toggle(settings.showsHandleWhenIdle, (v) =>
        commit((s) => (s.showsHandleWhenIdle = v)))),
      field("Reduce motion", null, toggle(settings.reduceMotion, (v) => commit((s) => (s.reduceMotion = v)))),
    ]),
  );
  return nodes;
}

const ACCENTS = ["#6E9BFF", "#7FD1AE", "#FFC46B", "#FF8A9B", "#C79BFF", "#8FE3F5", "#E8E8EA"];

function accentPicker() {
  const wrap = el("div", "field-control");
  for (const hex of ACCENTS) {
    const swatch = el("button");
    Object.assign(swatch.style, {
      width: "18px", height: "18px", borderRadius: "50%", background: hex,
      border: settings.accentHex.toLowerCase() === hex.toLowerCase()
        ? "2px solid #fff" : "1px solid rgba(255,255,255,0.2)",
      padding: "0", cursor: "default",
    });
    swatch.addEventListener("click", () => commit((s) => (s.accentHex = hex)));
    wrap.append(swatch);
  }
  const custom = el("input");
  custom.type = "color";
  custom.value = settings.accentHex;
  custom.addEventListener("change", () => commit((s) => (s.accentHex = custom.value.toUpperCase())));
  wrap.append(custom);
  return wrap;
}

/** Scale model of the panel on its display, so shape settings can be judged here. */
function preview() {
  const box = el("div");
  box.id = "preview";

  // The viewBox is in real screen points, so the panel is drawn at its true size and
  // SVG does the scaling — no manual scale factor to keep in sync.
  const stage = { width: 1512, height: 945 };
  const horizontal = growsHorizontally(settings.edge);
  const depth = horizontal ? settings.panelWidth : settings.panelHeight;
  const extent = horizontal ? settings.panelHeight : settings.panelWidth;
  const inverse = Math.min(14, settings.cornerRadius * 0.6);

  const width = horizontal ? depth : extent + 2 * inverse;
  const height = horizontal ? extent + 2 * inverse : depth;
  const path = notchPath(settings.edge, width, height, settings.cornerRadius, inverse);

  const svgNS = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(svgNS, "svg");
  svg.setAttribute("viewBox", `0 0 ${stage.width} ${stage.height}`);
  svg.setAttribute("preserveAspectRatio", "xMidYMid meet");

  const along = horizontal
    ? {
        x: settings.edge === "trailing" ? stage.width - width : 0,
        y: (stage.height - height) * settings.alignment,
      }
    : {
        x: (stage.width - width) * settings.alignment,
        y: settings.edge === "bottom" ? stage.height - height : 0,
      };

  const layer = document.createElementNS(svgNS, "g");
  layer.setAttribute("transform", `translate(${along.x} ${along.y})`);
  const shape = document.createElementNS(svgNS, "path");
  shape.setAttribute("d", path);
  shape.setAttribute("fill", "rgba(0,0,0,0.92)");
  shape.setAttribute("stroke", settings.accentHex);
  shape.setAttribute("stroke-opacity", "0.6");
  shape.setAttribute("stroke-width", "4");
  layer.append(shape);
  svg.append(layer);

  const stageBox = el("div", "preview-stage");
  stageBox.append(svg);
  box.append(stageBox, el("div", "hint", "open state, to scale"));
  return box;
}

const CHIPS = [
  ["clock", "Time", "Hours and minutes, stacked on the side edges."],
  ["date", "Date", "Day of the month and the weekday."],
  ["cpu", "CPU", "Total load, tinted as it climbs."],
  ["memory", "Memory", "Memory in use as a share of the total."],
  ["battery", "Battery", "Charge level, with a bolt while charging."],
  ["nowPlaying", "Now playing", "Lights up while something is playing."],
  ["clipboard", "Clipboard count", "How many entries are in the history."],
  ["widgetIcons", "Widget icons", "One glyph per widget in your panel."],
];
const SAMPLING_CHIPS = new Set(["cpu", "memory", "battery", "nowPlaying"]);

function idleHandleGroup() {
  const chosen = settings.handleChips ?? [];
  const children = [];

  const presets = [
    ["Line", []],
    ["Clock", ["clock"]],
    ["Now playing", ["clock", "nowPlaying"]],
    ["Widget icons", ["widgetIcons"]],
    ["System", ["cpu", "memory", "battery"]],
    ["Everything", ["clock", "nowPlaying", "cpu", "memory", "battery"]],
  ];
  const current = presets.find(([, chips]) => chips.join() === chosen.join());
  children.push(
    field("Preset", null, select(
      [...presets.map(([name]) => [name, name]), ...(current ? [] : [["Custom", "Custom"]])],
      current ? current[0] : "Custom",
      (name) => {
        const preset = presets.find(([label]) => label === name);
        if (preset) commit((s) => (s.handleChips = [...preset[1]]));
      },
    )),
  );

  if (!chosen.length) {
    children.push(el("div", "footnote", "The handle is a plain line. Add something below to make it show information."));
    children.push(field("Line thickness", null, slider(settings.handleThickness, 2, 16, 1, "pt", (v) =>
      commit((s) => (s.handleThickness = v)))));
    children.push(field("Line length", null, slider(settings.handleLength, 40, 320, 1, "pt", (v) =>
      commit((s) => (s.handleLength = v)))));
  } else {
    const list = el("div", "list");
    chosen.forEach((chipId, index) => {
      const meta = CHIPS.find(([id]) => id === chipId);
      if (!meta) return;
      const row = el("div", "list-row");
      row.draggable = true;
      row.addEventListener("dragstart", () => row.classList.add("dragging"));
      row.addEventListener("dragend", () => row.classList.remove("dragging"));
      row.addEventListener("dragover", (event) => {
        event.preventDefault();
        const dragging = list.querySelector(".dragging");
        if (!dragging || dragging === row) return;
        const from = [...list.children].indexOf(dragging);
        const to = [...list.children].indexOf(row);
        commit((s) => {
          const moved = s.handleChips.splice(from, 1)[0];
          s.handleChips.splice(to, 0, moved);
        });
      });
      const label = el("div");
      label.append(el("div", "title", meta[1]), el("div", "subtitle", meta[2]));
      row.append(el("span", "grip", "≡"), label, el("span", "spacer"));
      row.append(button("−", () => commit((s) => s.handleChips.splice(index, 1))));
      list.append(row);
    });
    children.push(list);
    children.push(field("Thickness", "How far the handle reaches out from the edge.",
      slider(settings.handleContentThickness, 20, 56, 1, "pt", (v) =>
        commit((s) => (s.handleContentThickness = v)))));
  }

  const available = CHIPS.filter(([id]) => !chosen.includes(id));
  if (available.length) {
    const chips = el("div", "chips");
    for (const [id, label] of available) {
      chips.append(button(label, () => commit((s) => s.handleChips.push(id)), "chip-add"));
    }
    children.push(chips);
  }

  const live = chosen.filter((id) => SAMPLING_CHIPS.has(id));
  const footnote = live.length
    ? `${live.map((id) => CHIPS.find(([c]) => c === id)[1]).join(", ")} keep sampling while the panel is closed, at a slower rate than when it is open.`
    : "Nothing here needs polling, so a closed panel costs nothing.";
  return group("Idle handle", children, footnote);
}

const PANES = {
  general: generalPane,
  appearance: appearancePane,
  widgets: () =>
    widgetsPane({
      settings, builtins, catalog, commit, expandedRow,
      setExpanded: (id) => { expandedRow = id; render(); },
    }),
  custom: () =>
    customPane({
      settings, builtins, catalog, commit, expandedRow,
      setExpanded: (id) => { expandedRow = id; render(); },
    }),
  about: () => aboutPane({ settings }),
};

const report = (what, detail) => {
  try {
    invoke("log_frontend", { message: `settings ${what}: ${detail}` });
  } catch {
    /* the bridge itself is gone */
  }
};
window.addEventListener("error", (event) => report("error", `${event.message} @ ${event.filename}:${event.lineno}`));
window.addEventListener("unhandledrejection", (event) => report("rejection", String(event.reason)));

function render() {
  if (!settings) return;
  document.documentElement.style.setProperty("--accent", settings.accentHex);
  for (const tab of document.querySelectorAll(".tab")) {
    tab.classList.toggle("active", tab.dataset.tab === activeTab);
  }
  const pane = document.getElementById("pane");
  try {
    pane.replaceChildren(...PANES[activeTab]());
  } catch (error) {
    // Leaving the previous pane on screen would look like a dead tab.
    report("pane failed", `${activeTab}: ${error?.name}: ${error?.message} | ${error?.stack ?? ""}`);
    pane.replaceChildren(el("div", "footnote", `This pane failed to render: ${error}`));
  }
}

async function start() {
  for (const tab of document.querySelectorAll(".tab")) {
    tab.addEventListener("click", () => {
      activeTab = tab.dataset.tab;
      expandedRow = null;
      render();
    });
  }

  const state = await invoke("get_state");
  settings = state.settings;
  [catalog, builtins, displays] = await Promise.all([
    invoke("list_widgets"),
    invoke("builtin_widgets"),
    invoke("list_displays"),
  ]);

  await listen("panel-state", (event) => {
    settings = event.payload.settings;
    render();
  });
  await listen("widgets", (event) => {
    catalog = event.payload;
    render();
  });

  render();
}

start();

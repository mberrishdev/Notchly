// The compiled-in widgets, rendered from data Rust pushes rather than polled here.

const el = (tag, className, html) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (html != null) node.innerHTML = html;
  return node;
};

const percent = (fraction) => `${Math.round((fraction ?? 0) * 100)}%`;

function formatBytes(bytes) {
  const value = Number(bytes) || 0;
  if (value < 1024) return `${value} B`;
  if (value < 1024 ** 2) return `${(value / 1024).toFixed(0)} KB`;
  if (value < 1024 ** 3) return `${(value / 1024 ** 2).toFixed(1)} MB`;
  return `${(value / 1024 ** 3).toFixed(2)} GB`;
}

function formatRate(bytesPerSecond) {
  const value = Math.max(0, Number(bytesPerSecond) || 0);
  if (value < 1024) return `${Math.round(value)} B/s`;
  if (value < 1024 ** 2) return `${(value / 1024).toFixed(0)} KB/s`;
  if (value < 1024 ** 3) return `${(value / 1024 ** 2).toFixed(1)} MB/s`;
  return `${(value / 1024 ** 3).toFixed(2)} GB/s`;
}

function formatDuration(seconds) {
  const total = Math.max(0, Math.floor(seconds ?? 0));
  const days = Math.floor(total / 86400);
  const hours = Math.floor((total % 86400) / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
}

function timecode(seconds) {
  const total = Math.max(0, Math.round(seconds ?? 0));
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

/** Tone for a load reading: quiet until it matters, then amber, then red. */
export function loadTone(fraction) {
  if (fraction < 0.6) return "normal";
  if (fraction < 0.85) return "caution";
  return "danger";
}

/**
 * A card is its content and nothing else.
 *
 * There was a header row here carrying the widget's name in small caps. It was removed
 * because a large clock, album art, or a search field says what it is far better than
 * the word above it does — and the row cost every widget 26px before its first reading.
 * The two widgets that genuinely are not self-evident label themselves, in their own
 * body, where the label can sit beside the thing it names.
 */
function card(body) {
  const node = el("section", "card");
  node.append(body);
  return node;
}

/**
 * A widget's own quiet label, for the ones a glance cannot place.
 *
 * `naming` marks the label as the widget's *name* rather than a heading within it. A
 * popover card puts the name in its own header, so a naming row there would say it
 * twice; a heading like UPTIME still belongs to the body and stays.
 */
function selfLabel(text, accessory, naming) {
  const row = el("div", `row baseline${naming ? " self-naming" : ""}`);
  row.append(el("span", "section-label", text), el("span", "card-spacer"));
  if (accessory) row.append(accessory);
  return row;
}

export function clockWidget(prefs) {
  const now = new Date();
  const use24 = (prefs.format ?? "24-hour") === "24-hour";
  const showSeconds = prefs.showSeconds === true;

  let hours = now.getHours();
  let suffix = "";
  if (!use24) {
    suffix = hours >= 12 ? "PM" : "AM";
    hours = hours % 12 || 12;
  }
  const parts = [use24 ? String(hours).padStart(2, "0") : String(hours)];
  parts.push(String(now.getMinutes()).padStart(2, "0"));
  if (showSeconds) parts.push(String(now.getSeconds()).padStart(2, "0"));

  const body = el("div", "card-body clock-body");
  body.append(
    el(
      "div",
      "clock-time",
      `${parts.join(":")}${suffix ? `<span class="clock-suffix">${suffix}</span>` : ""}`,
    ),
    el(
      "div",
      "clock-meta",
      `<span>${now.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}</span>
       <span class="muted">Week ${weekOfYear(now)}</span>`,
    ),
  );
  return card(body);
}

function weekOfYear(date) {
  const target = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const day = target.getUTCDay() || 7;
  target.setUTCDate(target.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(target.getUTCFullYear(), 0, 1));
  return Math.ceil(((target - yearStart) / 86400000 + 1) / 7);
}

export function systemWidget(metrics, history, prefs) {
  const body = el("div", "card-body");

  const cpuRow = el("div", "row baseline");
  cpuRow.append(
    el("span", "label", "CPU"),
    el("span", "card-spacer"),
    el("span", `stat big tone-${loadTone(metrics.cpu ?? 0)}`, percent(metrics.cpu)),
  );
  body.append(cpuRow, sparkline(history));

  body.append(meterRow("Memory", metrics.memory, `${formatBytes(metrics.memoryUsed)} of ${formatBytes(metrics.memoryTotal)}`));
  if (prefs.showDisk !== false) {
    body.append(meterRow("Disk", metrics.disk, `${formatBytes(metrics.diskFree)} free`));
  }
  if (prefs.showNetwork !== false) {
    const net = el("div", "row baseline");
    net.append(
      el("span", "label", "Network"),
      el("span", "card-spacer"),
      el("span", "stat small", `↓ ${formatRate(metrics.networkDown)}`),
      el("span", "stat small", `↑ ${formatRate(metrics.networkUp)}`),
    );
    body.append(net);
  }
  if (prefs.showBattery !== false && metrics.battery?.present) {
    const battery = metrics.battery;
    const detail = battery.charging
      ? battery.minutesRemaining
        ? `${formatDuration(battery.minutesRemaining * 60)} to full`
        : "Charging"
      : battery.minutesRemaining
        ? `${formatDuration(battery.minutesRemaining * 60)} remaining`
        : "On battery";
    body.append(meterRow(battery.charging ? "Battery ⚡" : "Battery", battery.level, detail));
  }
  if (prefs.showProcesses !== false && metrics.topProcesses?.length) {
    body.append(el("div", "section-label", "TOP PROCESSES"));
    for (const process of metrics.topProcesses.slice(0, 3)) {
      const row = el("div", "row");
      row.append(
        el("span", "process-name", process.name),
        el("span", "card-spacer"),
        el("span", "stat tiny muted", formatBytes(process.memory)),
        el("span", `stat tiny tone-${loadTone(process.cpu)}`, percent(process.cpu)),
      );
      body.append(row);
    }
  }

  // Uptime rode in the header; it belongs with the readings it describes.
  body.append(selfLabel("UPTIME", el("span", "accessory", formatDuration(metrics.uptime))));
  return card(body);
}

function meterRow(label, fraction, detail) {
  const wrap = el("div", "meter-row");
  const top = el("div", "row baseline");
  top.append(
    el("span", "label", label),
    el("span", "card-spacer"),
    el("span", "stat tiny muted", detail ?? ""),
    el("span", "stat", percent(fraction)),
  );
  const track = el("div", "meter");
  const fill = el("div", `meter-fill tone-${loadTone(fraction ?? 0)}`);
  fill.style.width = `${Math.min(100, Math.max(0, (fraction ?? 0) * 100))}%`;
  track.append(fill);
  wrap.append(top, track);
  return wrap;
}

/** Filled line chart for the CPU history strip. */
function sparklinePath(values, width, height) {
  if (!values || values.length < 2) return "";
  const step = width / (values.length - 1);
  return values
    .map((value, index) => {
      const x = index * step;
      const y = height * (1 - Math.min(1, Math.max(0, value)));
      return `${index === 0 ? "M" : "L"}${x.toFixed(1)} ${y.toFixed(1)}`;
    })
    .join("");
}

function sparkline(history) {
  const width = 300;
  const height = 30;
  const line = sparklinePath(history, width, height);
  const svg = el("div", "sparkline");
  svg.innerHTML = `<svg viewBox="0 0 ${width} ${height}" preserveAspectRatio="none">
    <path d="${line}L${width} ${height}L0 ${height}Z" class="spark-fill" />
    <path d="${line}" class="spark-line" />
  </svg>`;
  return svg;
}

export function mediaWidget(media) {
  const body = el("div", "card-body");
  if (!media || !media.title) {
    body.append(el("div", "empty", "Nothing playing<br><span class='muted'>Start something in Music or Spotify.</span>"));
    return card(body);
  }

  body.append(
    el("div", "media-title", escapeHtml(media.title)),
    el("div", "media-artist", escapeHtml(media.artist || media.app || "")),
  );
  if (media.duration > 0) {
    const track = el("div", "meter");
    const fill = el("div", "meter-fill accent");
    fill.style.width = `${Math.min(100, (media.position / media.duration) * 100)}%`;
    track.append(fill);
    const times = el("div", "row tiny muted");
    times.append(
      el("span", null, timecode(media.position)),
      el("span", "card-spacer"),
      el("span", null, `-${timecode(media.duration - media.position)}`),
    );
    body.append(track, times);
  }

  const controls = el("div", "row controls");
  for (const [label, method] of [
    ["⏮", "media.previous"],
    [media.playing ? "⏸" : "▶", "media.playPause"],
    ["⏭", "media.next"],
  ]) {
    const button = el("button", "transport", label);
    button.dataset.method = method;
    controls.append(button);
  }
  body.append(controls);
  return card(body);
}

export function clipboardWidget(entries, prefs) {
  const body = el("div", "card-body");
  const limit = prefs.visibleCount ?? 6;
  body.append(selfLabel("CLIPBOARD", el("span", "accessory", String(entries?.length ?? 0)), true));
  if (!entries?.length) {
    body.append(el("div", "empty", "Nothing copied yet<br><span class='muted'>Copy something and it lands here.</span>"));
    return card(body);
  }
  for (const entry of entries.slice(0, limit)) {
    const row = el("button", "clip-row");
    row.dataset.clipId = entry.id;
    row.append(
      el("span", "clip-kind", { url: "↗", color: "◼", text: "≡" }[entry.kind] ?? "≡"),
      el("span", "clip-text", escapeHtml(entry.text.replace(/\s+/g, " ").trim().slice(0, 120))),
    );
    body.append(row);
  }
  return card(body);
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c],
  );
}

export function launcherWidget() {
  const body = el("div", "card-body");
  const field = el("div", "search-field");
  field.innerHTML = `<span class="search-icon">⌕</span>
    <input id="launcher-input" type="text" placeholder="Search apps" spellcheck="false" />`;
  const results = el("div", "launcher-results");
  results.id = "launcher-results";
  body.append(field, results);
  return card(body);
}

export function renderLauncherResults(container, apps, selected) {
  container.replaceChildren();
  if (!apps.length) return;
  apps.forEach((app, index) => {
    const row = el("button", `launcher-row${index === selected ? " selected" : ""}`);
    row.dataset.path = app.path;
    row.append(
      el("span", "launcher-initial", app.name.charAt(0).toUpperCase()),
      el("span", "launcher-name", app.name),
    );
    container.append(row);
  });
}

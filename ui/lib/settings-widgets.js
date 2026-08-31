// The Widgets, Custom Widgets and About panes.

import { invoke } from "./bridge.js";
import { el, field, toggle, button, group, schemaField } from "./settings-controls.js";

const PERMISSION_DETAIL = {
  network: ["Network access", "Lets the widget load remote pages and call APIs."],
  shell: ["Run shell commands", "Lets the widget run commands as you. Only grant this to widgets you trust."],
  system: ["Read system stats", "CPU, memory, disk, network and battery readings."],
  clipboard: ["Read clipboard history", "The text and links you have copied recently."],
  notifications: ["Post notifications", "Banners in Notification Center."],
};
/** The permissions the user must approve by hand. Mirrors `requires_explicit_grant`. */
const GRANTABLE = ["network", "shell", "clipboard"];
const GRANT_LIST = {
  network: "networkApprovedWidgets",
  shell: "shellApprovedWidgets",
  clipboard: "clipboardApprovedWidgets",
};

function descriptorFor(ctx, widgetId) {
  const builtin = ctx.builtins?.find((d) => d.id === widgetId);
  if (builtin) return { ...builtin, kind: "builtIn", permissions: [] };
  const pkg = ctx.catalog.packages.find((p) => p.manifest.id === widgetId);
  if (!pkg) return null;
  return {
    id: pkg.manifest.id,
    name: pkg.manifest.name,
    summary: pkg.manifest.description ?? "Custom widget",
    settings: pkg.manifest.settings ?? [],
    permissions: pkg.manifest.permissions ?? [],
    kind: "web",
    version: pkg.manifest.version,
    author: pkg.manifest.author,
    folder: pkg.folder,
  };
}

function isGranted(settings, widgetId, permission) {
  if (!GRANTABLE.includes(permission)) return true;
  return (settings[GRANT_LIST[permission]] ?? []).includes(widgetId);
}

function permissionList(ctx, descriptor) {
  const wrap = el("div");
  wrap.append(el("h2", null, "Permissions"));
  if (!descriptor.permissions.length) {
    wrap.append(el("div", "footnote", "This widget asked for nothing beyond drawing itself."));
    return wrap;
  }
  for (const permission of [...descriptor.permissions].sort()) {
    const [label, detail] = PERMISSION_DETAIL[permission] ?? [permission, ""];
    const granted = isGranted(ctx.settings, descriptor.id, permission);
    const control = GRANTABLE.includes(permission)
      ? toggle(granted, (value) =>
          ctx.commit((s) => {
            const key = GRANT_LIST[permission];
            const list = new Set(s[key] ?? []);
            value ? list.add(descriptor.id) : list.delete(descriptor.id);
            s[key] = [...list];
          }),
        )
      : el("span", "badge", "Granted");
    wrap.append(field(label, detail, control));
  }
  return wrap;
}

function settingsForm(ctx, descriptor) {
  if (!descriptor.settings?.length) return null;
  const wrap = el("div");
  wrap.append(el("h2", null, "Settings"));
  const slot = ctx.settings.slots.find((s) => s.widgetId === descriptor.id);
  for (const spec of descriptor.settings) {
    const current = slot?.preferences?.[spec.key];
    wrap.append(
      schemaField(spec, current, (value) =>
        ctx.commit((s) => {
          const target = s.slots.find((item) => item.widgetId === descriptor.id);
          if (target) target.preferences = { ...target.preferences, [spec.key]: value };
        }),
      ),
    );
  }
  return wrap;
}

export function widgetsPane(ctx) {
  const nodes = [];
  const list = el("div", "list");

  ctx.settings.slots.forEach((slot, index) => {
    const descriptor = descriptorFor(ctx, slot.widgetId);
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
      ctx.commit((s) => {
        const moved = s.slots.splice(from, 1)[0];
        s.slots.splice(to, 0, moved);
      });
    });

    const label = el("div");
    label.append(
      el("div", "title", descriptor?.name ?? slot.widgetId),
      el("div", "subtitle", descriptor?.summary ?? "This widget is no longer installed."),
    );
    row.append(el("span", "grip", "≡"), label, el("span", "spacer"));

    if (descriptor?.kind === "web") row.append(el("span", "badge", "Custom"));
    if (descriptor && (descriptor.settings?.length || descriptor.permissions?.length)) {
      row.append(button(ctx.expandedRow === slot.id ? "▾" : "▸", () =>
        ctx.setExpanded(ctx.expandedRow === slot.id ? null : slot.id)));
    }
    row.append(
      toggle(slot.isEnabled, (value) =>
        ctx.commit((s) => (s.slots[index].isEnabled = value))),
      button("−", () => ctx.commit((s) => s.slots.splice(index, 1))),
    );
    list.append(row);

    if (ctx.expandedRow === slot.id && descriptor) {
      const detail = el("div", "disclosure");
      const form = settingsForm(ctx, descriptor);
      if (form) detail.append(form);
      if (descriptor.kind === "web") detail.append(permissionList(ctx, descriptor));
      list.append(detail);
    }
  });

  nodes.push(
    group("In your panel", [
      ctx.settings.slots.length ? list : el("div", "footnote", "No widgets yet — add one below."),
    ], "Drag rows to reorder. The panel updates as you go."),
  );

  const used = new Set(ctx.settings.slots.map((s) => s.widgetId));
  const available = [
    ...ctx.builtins.map((d) => ({ ...d, kind: "builtIn" })),
    ...ctx.catalog.packages.map((p) => ({
      id: p.manifest.id,
      name: p.manifest.name,
      summary: p.manifest.description ?? "Custom widget",
      kind: "web",
    })),
  ].filter((d) => !used.has(d.id));

  const availableList = el("div", "list");
  for (const descriptor of available) {
    const row = el("div", "list-row");
    const label = el("div");
    label.append(el("div", "title", descriptor.name), el("div", "subtitle", descriptor.summary));
    row.append(label, el("span", "spacer"));
    if (descriptor.kind === "web") row.append(el("span", "badge", "Custom"));
    row.append(
      button("Add", () =>
        ctx.commit((s) =>
          s.slots.push({
            id: `slot-${Date.now()}-${descriptor.id}`,
            kind: descriptor.kind,
            widgetId: descriptor.id,
            isEnabled: true,
            preferences: {},
          }),
        ),
      ),
    );
    availableList.append(row);
  }

  nodes.push(
    group("Available", [
      available.length
        ? availableList
        : el("div", "footnote", "Every widget Notchly knows about is already in your panel."),
    ]),
  );
  return nodes;
}

export function customPane(ctx) {
  const nodes = [];
  const nameInput = el("input");
  nameInput.type = "text";
  nameInput.placeholder = "New widget name";

  nodes.push(
    group("Widgets folder", [
      field("Location", null, button("Reveal", () => invoke("open_widgets_folder"))),
      field("Create a widget", "Scaffolds a working widget.json and index.html.", [
        nameInput,
        button("Create", async () => {
          await invoke("create_starter_widget", { name: nameInput.value });
          nameInput.value = "";
          invoke("open_widgets_folder");
        }, "action primary"),
      ]),
      field("Maintenance", null, [
        button("Reload All", () => invoke("reload_all_widgets")),
        button("Reinstall Examples", () => invoke("reinstall_examples")),
      ]),
    ], "Each widget is a folder with a widget.json and an HTML entry point. Save a file and Notchly reloads it — no restart, no rebuild."),
  );

  if (ctx.catalog.failures.length) {
    const problems = ctx.catalog.failures.map((failure) => {
      const row = el("div", "problem");
      const body = el("div");
      body.append(
        el("div", "title", failure.folder.split("/").pop()),
        el("div", "subtitle", failure.reason),
      );
      row.append(el("span", "icon", "⚠"), body);
      return row;
    });
    nodes.push(group("Could not load", problems));
  }

  const installed = el("div", "list");
  for (const pkg of ctx.catalog.packages) {
    const inPanel = ctx.settings.slots.some((s) => s.widgetId === pkg.manifest.id);
    const row = el("div", "list-row");
    const label = el("div");
    label.append(
      el("div", "title", `${pkg.manifest.name}${pkg.manifest.version ? ` v${pkg.manifest.version}` : ""}`),
      el("div", "subtitle", pkg.manifest.description ?? ""),
    );
    row.append(label, el("span", "spacer"));
    row.append(
      inPanel
        ? el("span", "badge accent", "In panel")
        : button("Add to Panel", () =>
            ctx.commit((s) =>
              s.slots.push({
                id: `slot-${Date.now()}-${pkg.manifest.id}`,
                kind: "web",
                widgetId: pkg.manifest.id,
                isEnabled: true,
                preferences: {},
              }),
            ),
          ),
      button("Reload", () => invoke("reload_widget", { widgetId: pkg.manifest.id })),
      button(ctx.expandedRow === pkg.manifest.id ? "▾" : "▸", () =>
        ctx.setExpanded(ctx.expandedRow === pkg.manifest.id ? null : pkg.manifest.id)),
    );
    installed.append(row);

    if (ctx.expandedRow === pkg.manifest.id) {
      const detail = el("div", "disclosure");
      detail.append(el("div", "mono subtitle", pkg.folder));
      const descriptor = descriptorFor(ctx, pkg.manifest.id);
      const form = settingsForm(ctx, descriptor);
      if (form) detail.append(form);
      detail.append(permissionList(ctx, descriptor));

      const logBox = el("div", "log");
      logBox.append(el("div", null, "Loading…"));
      invoke("widget_log", { widgetId: pkg.manifest.id }).then((lines) => {
        logBox.replaceChildren();
        if (!lines.length) {
          logBox.append(el("div", null, "Nothing logged. Call notchly.log() from your widget."));
        } else {
          for (const line of lines.slice(-40)) logBox.append(el("div", "mono", line));
        }
      });
      detail.append(el("h2", null, "Log"), logBox);
      installed.append(detail);
    }
  }

  nodes.push(
    group(`Installed (${ctx.catalog.packages.length})`, [
      ctx.catalog.packages.length
        ? installed
        : el("div", "footnote", "Nothing installed yet. Create a starter widget above to see the shape of one."),
    ]),
  );

  const API = [
    ["notchly.system.stats()", "CPU, memory, disk, network, battery, uptime"],
    ["notchly.storage.get/set/remove", "Per-widget key/value store, persisted"],
    ["notchly.settings.get(key) / .all()", "Values from your widget.json settings schema"],
    ["notchly.media.now() / playPause()", "Now playing and transport"],
    ["notchly.clipboard.history(limit)", "Clipboard history (needs permission)"],
    ["notchly.http.get(url) / .json(url)", "Network fetch (needs permission)"],
    ["notchly.shell.run(command)", "Run a command (needs explicit approval)"],
    ["notchly.ui.resize(h) / holdOpen(b)", "Control the panel around you"],
    ["--notchly-accent, --notchly-text", "CSS variables injected into your page"],
  ].map(([sig, desc]) => {
    const row = el("div", "api-row");
    row.append(el("code", "sig mono", sig), el("span", "desc", desc));
    return row;
  });
  nodes.push(group("API", API,
    "Everything on window.notchly returns a promise. Permissions your widget hasn't been granted reject with a readable message."));
  return nodes;
}

export function aboutPane(ctx) {
  const shortcuts = [
    ["Toggle the panel", ctx.settings.hotkey.accelerator || "None"],
    ["Close the panel", "Esc"],
    ["Launch highlighted app", "Return"],
    ["Move the panel", "Drag the handle, or the grip when open"],
  ].map(([label, keys]) => {
    const row = el("div", "field");
    row.append(el("div", "field-label", label));
    const wrap = el("div", "field-control");
    wrap.append(el("kbd", null, keys));
    row.append(wrap);
    return row;
  });

  const privacy = [
    "Notchly makes no network requests of its own beyond checking for updates.",
    "Custom widgets are offline by default — network access is a per-widget switch.",
    "Shell access is off unless you turn it on for a specific widget.",
    "Clipboard history is stored unencrypted in Application Support.",
  ].map((line) => el("div", "footnote", `• ${line}`));

  return [
    group("Notchly", [
      el("div", "footnote", "A notch-shaped panel that docks to any edge of your display."),
      versionRow(),
    ]),
    group("Shortcuts", shortcuts),
    group("Privacy", privacy),
  ];
}

/**
 * Version, and a check that reports what it found — including why it failed.
 *
 * A check that quietly says "up to date" when it could not reach the network is worse
 * than no check at all, so the three outcomes are distinct.
 */
function versionRow() {
  const wrap = el("div");
  const status = el("div", "footnote", "");
  const action = el("button", "action", "Check for Updates");
  const version = el("div", "field");
  version.append(el("div", "field-label", "Version"));
  const control = el("div", "field-control");
  control.append(el("span", "readout mono", "…"), action);
  version.append(control);
  wrap.append(version, status);

  const readout = control.querySelector(".readout");
  invoke("app_version").then((v) => {
    readout.textContent = v;
  });

  let installing = false;
  action.addEventListener("click", async () => {
    if (installing) return;
    action.disabled = true;
    action.textContent = "Checking…";
    status.textContent = "";

    let result;
    try {
      result = await invoke("check_update");
    } catch (error) {
      result = { status: "failed", reason: String(error?.message ?? error) };
    }

    action.disabled = false;
    if (result.status === "upToDate") {
      action.textContent = "Check for Updates";
      status.textContent = `Notchly ${result.version} is the latest version.`;
      return;
    }
    if (result.status === "failed") {
      action.textContent = "Check for Updates";
      status.textContent = `Couldn't check for updates: ${result.reason}`;
      return;
    }

    action.textContent = `Install ${result.version}`;
    status.textContent = result.notes
      ? `Version ${result.version} is available.\n${result.notes}`
      : `Version ${result.version} is available. Notchly will restart to finish.`;
    action.onclick = async () => {
      installing = true;
      action.disabled = true;
      action.textContent = "Installing…";
      try {
        await invoke("install_update");
      } catch (error) {
        installing = false;
        action.disabled = false;
        action.textContent = `Install ${result.version}`;
        status.textContent = `Update failed: ${String(error?.message ?? error)}`;
      }
    };
  });

  return wrap;
}

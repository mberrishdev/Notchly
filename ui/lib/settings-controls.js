// Pure DOM helpers shared by every settings pane.
//
// Kept free of state so the panes can import them without importing each other —
// a circular import between panes would leave these in the temporal dead zone.

export const el = (tag, className, text) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
};

export function field(name, help, control) {
  const row = el("div", "field");
  const label = el("div", "field-label");
  label.append(el("div", "name", name));
  if (help) label.append(el("div", "help", help));
  const wrap = el("div", "field-control");
  wrap.append(...(Array.isArray(control) ? control : [control]));
  row.append(label, wrap);
  return row;
}

export function toggle(value, onChange) {
  const node = el("button", "switch");
  node.setAttribute("aria-checked", String(Boolean(value)));
  node.addEventListener("click", () => onChange(!value));
  return node;
}

export function slider(value, min, max, step, unit, onChange) {
  const input = el("input");
  input.type = "range";
  Object.assign(input, { min, max, step, value });
  const readout = el("span", "readout", `${Math.round(value)}${unit}`);
  input.addEventListener("input", () => {
    readout.textContent = `${Math.round(Number(input.value))}${unit}`;
  });
  input.addEventListener("change", () => onChange(Number(input.value)));
  return [input, readout];
}

export function segmented(options, current, onChange) {
  const group = el("div", "segmented");
  for (const [value, label] of options) {
    const node = el("button", value === current ? "active" : null, label);
    node.addEventListener("click", () => onChange(value));
    group.append(node);
  }
  return group;
}

export function select(options, current, onChange) {
  const node = el("select");
  for (const [value, label] of options) {
    const option = el("option", null, label);
    option.value = value;
    if (value === current) option.selected = true;
    node.append(option);
  }
  node.addEventListener("change", () => onChange(node.value));
  return node;
}

/**
 * A credential field. It never shows what is stored — the store is write-only from
 * here — so the control reports whether something is filed and offers to replace it.
 * Emptying the box and saving is how a secret is deleted.
 */
function secretInput(secret) {
  const row = el("div", "secret-row");
  const input = el("input");
  input.type = "password";
  input.autocomplete = "off";
  input.placeholder = "Paste a token";

  const status = el("span", "secret-status", "Checking…");
  const save = el("button", "action", "Save");

  const show = (stored) => {
    status.textContent = stored ? "Stored" : "Not set";
    input.placeholder = stored ? "Stored — type to replace" : "Paste a token";
  };
  secret?.isSet?.().then(show).catch(() => show(false));

  save.addEventListener("click", async () => {
    const entered = input.value;
    save.disabled = true;
    try {
      await secret?.onSave?.(entered);
      input.value = "";
      show(entered.length > 0);
    } catch (error) {
      status.textContent = String(error);
    } finally {
      save.disabled = false;
    }
  });

  row.append(input, save, status);
  return row;
}

function textInput(value, onChange, placeholder) {
  const input = el("input");
  input.type = "text";
  input.value = value ?? "";
  if (placeholder) input.placeholder = placeholder;
  input.addEventListener("change", () => onChange(input.value));
  return input;
}

export function button(label, onClick, className = "action") {
  const node = el("button", className, label);
  node.addEventListener("click", onClick);
  return node;
}

export function group(title, children, footnote) {
  const section = el("section", "group");
  section.append(el("h2", null, title));
  const card = el("div", "card");
  card.append(...children.filter(Boolean));
  section.append(card);
  if (footnote) section.append(el("div", "footnote", footnote));
  return section;
}

/**
 * Renders one declared widget setting as a native control.
 *
 * Built-ins and custom widgets both come through here, so a folder the user drops in
 * gets exactly the same controls as Now Playing.
 */
export function schemaField(spec, current, onChange, secret) {
  const value = current ?? spec.default;
  switch (spec.type) {
    case "secret":
      return field(spec.label, spec.help, secretInput(secret));
    case "boolean":
      return field(spec.label, spec.help, toggle(value === true, onChange));
    case "number":
      return field(
        spec.label,
        spec.help,
        slider(Number(value ?? spec.minimum ?? 0), spec.minimum ?? 0, spec.maximum ?? 100, 1, "", onChange),
      );
    case "select":
      return field(spec.label, spec.help, select((spec.options ?? []).map((o) => [o, o]), value, onChange));
    case "color": {
      const input = el("input");
      input.type = "color";
      input.value = value ?? "#6E9BFF";
      input.addEventListener("change", () => onChange(input.value.toUpperCase()));
      return field(spec.label, spec.help, input);
    }
    default:
      return field(spec.label, spec.help, textInput(value ?? "", onChange));
  }
}

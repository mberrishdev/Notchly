// Thin wrapper over the Tauri command surface, so the rest of the frontend never
// touches `window.__TAURI__` directly and can be reasoned about on its own.

const tauri = () => window.__TAURI__;

export const invoke = (command, args) => tauri().core.invoke(command, args);
export const listen = (event, handler) => tauri().event.listen(event, handler);

export const panel = {
  open: () => invoke("open_panel"),
  close: () => invoke("close_panel"),
  toggle: () => invoke("toggle_panel"),
  state: () => invoke("get_state"),
  beginDrag: () => invoke("begin_drag"),
  drag: () => invoke("drag_panel"),
  endDrag: () => invoke("end_drag"),
  updateSettings: (settings) => invoke("update_settings", { settings }),
};

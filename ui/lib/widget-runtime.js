// The `window.notchly` surface, injected into every custom widget.
//
// The widget runs in a sandboxed iframe with an opaque origin, so it can't call Tauri
// directly. Every call is posted to the host page, which checks the widget's granted
// permissions and forwards it to Rust. Authors still just write `await` — the plumbing
// is invisible from inside the widget.
(function () {
  if (window.notchly) return;

  const config = window.__NOTCHLY_WIDGET__ || { id: "", settings: {}, theme: {} };
  const pending = new Map();
  let sequence = 0;
  let autoHeight = true;
  let lastReportedHeight = 0;

  function post(method, params) {
    return new Promise((resolve, reject) => {
      const id = ++sequence;
      pending.set(id, { resolve, reject });
      parent.postMessage(
        { __notchly: true, widgetId: config.id, id, method, params: params || {} },
        "*",
      );
    });
  }

  window.addEventListener("message", (event) => {
    const data = event.data;
    if (!data || data.__notchlyReply !== true) return;
    const entry = pending.get(data.id);
    if (!entry) return;
    pending.delete(data.id);
    if (data.error) entry.reject(new Error(data.error));
    else entry.resolve(data.result);
  });

  function measure() {
    if (!autoHeight || !document.body) return;
    const height = Math.ceil(
      Math.max(document.body.scrollHeight, document.body.getBoundingClientRect().height),
    );
    if (height > 0 && Math.abs(height - lastReportedHeight) > 1) {
      lastReportedHeight = height;
      post("ui.resize", { height });
    }
  }

  const api = {
    version: "1.0",
    call: post,
    system: {
      stats: () => post("system.stats"),
      info: () => post("system.info"),
    },
    storage: {
      get: (key) => post("storage.get", { key }),
      set: (key, value) => post("storage.set", { key, value }),
      remove: (key) => post("storage.remove", { key }),
      keys: () => post("storage.keys"),
      clear: () => post("storage.clear"),
    },
    settings: {
      get: (key) => post("settings.get", { key }),
      all: () => post("settings.all"),
    },
    media: {
      now: () => post("media.now"),
      playPause: () => post("media.playPause"),
      next: () => post("media.next"),
      previous: () => post("media.previous"),
    },
    clipboard: {
      history: (limit) => post("clipboard.history", { limit }),
      write: (text) => post("clipboard.write", { text }),
    },
    shell: {
      run: (command, timeout) => post("shell.run", { command, timeout }),
    },
    http: {
      get: (url, headers) => post("http.get", { url, headers }),
      json: async (url, headers) => JSON.parse((await post("http.get", { url, headers })).body),
      // { url, method, headers, body } — a non-string body is sent as JSON.
      request: (options) => post("http.request", options ?? {}),
      post: (url, body, headers) => post("http.request", { url, method: "POST", body, headers }),
    },
    open: (url) => post("open.url", { url }),
    notify: (title, body) => post("notify", { title, body }),
    log: (...args) =>
      post("log", {
        message: args.map((v) => (typeof v === "string" ? v : JSON.stringify(v))).join(" "),
      }),
    ui: {
      resize: (height) => post("ui.resize", { height }),
      close: () => post("ui.close"),
      theme: () => post("ui.theme"),
      holdOpen: (value) => post("ui.holdOpen", { value: value !== false }),
      autoHeight: (enabled) => {
        autoHeight = enabled !== false;
        measure();
      },
    },
    on: (event, handler) => {
      const wrapped = (e) => handler(e.detail);
      window.addEventListener("notchly:" + event, wrapped);
      return () => window.removeEventListener("notchly:" + event, wrapped);
    },
  };

  for (const group of ["system", "storage", "settings", "media", "clipboard", "shell", "http"]) {
    Object.freeze(api[group]);
  }
  window.notchly = api;

  // Surface widget failures in Notchly's per-widget log rather than a console no one
  // is watching.
  const originalError = window.console.error.bind(window.console);
  window.console.error = function (...args) {
    api.log(...args);
    originalError(...args);
  };
  window.addEventListener("error", (event) => api.log("Error:", event.message));
  window.addEventListener("unhandledrejection", (event) =>
    api.log("Unhandled rejection:", String(event.reason)),
  );

  function applyTheme(theme) {
    const root = document.documentElement;
    if (!root) return;
    Object.keys(theme || {}).forEach((key) =>
      root.style.setProperty("--notchly-" + key, theme[key]),
    );
    window.dispatchEvent(new CustomEvent("notchly:theme", { detail: theme }));
  }
  window.__notchlyApplyTheme = applyTheme;
  window.__notchlyEmit = (name, detail) =>
    window.dispatchEvent(new CustomEvent("notchly:" + name, { detail }));
  applyTheme(config.theme);

  const ready = () => {
    applyTheme(config.theme);
    measure();
    if (window.ResizeObserver && document.body) new ResizeObserver(measure).observe(document.body);
  };
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ready);
  } else {
    ready();
  }
})();

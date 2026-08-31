import Foundation

enum WebWidgetRuntime {
    static func api(theme: String, autoHeight: Bool) -> String {
        """
        (function () {
          if (window.notchly) { return; }
          const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.notchly;
          const post = (method, params) => {
            if (!bridge) { return Promise.reject(new Error('Notchly bridge unavailable')); }
            return bridge.postMessage({ method: method, params: params || {} });
          };

          let autoHeight = \(autoHeight ? "true" : "false");
          let lastReported = 0;

          function measure() {
            if (!autoHeight || !document.body) { return; }
            const height = Math.ceil(Math.max(
              document.body.scrollHeight,
              document.body.getBoundingClientRect().height
            ));
            if (height > 0 && Math.abs(height - lastReported) > 1) {
              lastReported = height;
              post('ui.resize', { height: height });
            }
          }

          const api = {
            version: '1.0',
            call: post,
            system: {
              stats: () => post('system.stats'),
              info: () => post('system.info')
            },
            storage: {
              get: (key) => post('storage.get', { key: key }),
              set: (key, value) => post('storage.set', { key: key, value: value }),
              remove: (key) => post('storage.remove', { key: key }),
              keys: () => post('storage.keys'),
              clear: () => post('storage.clear')
            },
            settings: {
              get: (key) => post('settings.get', { key: key }),
              all: () => post('settings.all')
            },
            media: {
              now: () => post('media.now'),
              playPause: () => post('media.playPause'),
              next: () => post('media.next'),
              previous: () => post('media.previous')
            },
            clipboard: {
              history: (limit) => post('clipboard.history', { limit: limit }),
              write: (text) => post('clipboard.write', { text: text })
            },
            shell: {
              run: (command, timeout) => post('shell.run', { command: command, timeout: timeout })
            },
            http: {
              get: (url, headers) => post('http.get', { url: url, headers: headers }),
              json: async (url, headers) => {
                const response = await post('http.get', { url: url, headers: headers });
                return JSON.parse(response.body);
              }
            },
            open: (url) => post('open.url', { url: url }),
            notify: (title, body) => post('notify', { title: title, body: body }),
            log: function () {
              const parts = Array.prototype.slice.call(arguments).map((value) =>
                typeof value === 'string' ? value : JSON.stringify(value)
              );
              return post('log', { message: parts.join(' ') });
            },
            ui: {
              resize: (height) => post('ui.resize', { height: height }),
              close: () => post('ui.close'),
              theme: () => post('ui.theme'),
              holdOpen: (value) => post('ui.holdOpen', { value: value !== false }),
              autoHeight: (enabled) => { autoHeight = enabled !== false; measure(); }
            },
            on: (event, handler) => {
              const wrapped = (e) => handler(e.detail);
              window.addEventListener('notchly:' + event, wrapped);
              return () => window.removeEventListener('notchly:' + event, wrapped);
            }
          };

          Object.freeze(api.system);
          Object.freeze(api.storage);
          Object.freeze(api.settings);
          Object.freeze(api.media);
          Object.freeze(api.clipboard);
          window.notchly = api;

          // Surface widget console output in Notchly's widget log.
          const originalError = window.console.error.bind(window.console);
          window.console.error = function () {
            api.log.apply(null, arguments);
            originalError.apply(null, arguments);
          };
          window.addEventListener('error', (e) => api.log('Error:', e.message));
          window.addEventListener('unhandledrejection', (e) => api.log('Unhandled rejection:', String(e.reason)));

          window.__notchlyApplyTheme = function (theme) {
            const root = document.documentElement;
            if (!root) { return; }
            Object.keys(theme).forEach((key) => root.style.setProperty('--notchly-' + key, theme[key]));
            window.dispatchEvent(new CustomEvent('notchly:theme', { detail: theme }));
          };
          window.__notchlyEmit = function (name, detail) {
            window.dispatchEvent(new CustomEvent('notchly:' + name, { detail: detail }));
          };
          window.__notchlyApplyTheme(\(theme));

          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => {
              window.__notchlyApplyTheme(\(theme));
              measure();
              if (window.ResizeObserver && document.body) {
                new ResizeObserver(measure).observe(document.body);
              }
            });
          } else {
            measure();
            if (window.ResizeObserver && document.body) {
              new ResizeObserver(measure).observe(document.body);
            }
          }
        })();
        """
    }

    /// Baseline styling so widgets sit on Notchly's card instead of a white page.
    /// Injected as the first stylesheet, so any rule a widget writes overrides it.
    static let baseStyle = """
    (function () {
      const css = `
        html, body { background: transparent !important; }
        body {
          margin: 0;
          -webkit-font-smoothing: antialiased;
          font: 13px -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
          color: var(--notchly-text, rgba(255,255,255,0.92));
          overflow-x: hidden;
        }
        ::-webkit-scrollbar { width: 0; height: 0; }
        a { color: var(--notchly-accent, #6E9BFF); }
        :focus-visible { outline: 2px solid var(--notchly-accent, #6E9BFF); outline-offset: 2px; }
      `;
      const style = document.createElement('style');
      style.setAttribute('data-notchly', 'base');
      style.textContent = css;
      const attach = () => {
        const head = document.head || document.documentElement;
        if (head.firstChild) { head.insertBefore(style, head.firstChild); } else { head.appendChild(style); }
      };
      if (document.head || document.documentElement) { attach(); }
      else { document.addEventListener('DOMContentLoaded', attach); }
    })();
    """

    /// Blocks every network load for widgets that didn't ask for (or weren't granted)
    /// network access, while leaving their own files reachable.
    static let offlineRuleList = """
    [
      { "trigger": { "url-filter": ".*" }, "action": { "type": "block" } },
      { "trigger": { "url-filter": "^file://" }, "action": { "type": "ignore-previous-rules" } },
      { "trigger": { "url-filter": "^data:" }, "action": { "type": "ignore-previous-rules" } },
      { "trigger": { "url-filter": "^about:" }, "action": { "type": "ignore-previous-rules" } }
    ]
    """
}

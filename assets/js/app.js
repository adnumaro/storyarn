/**
 * Storyarn — Vue + LiveView entry point.
 *
 * Loaded via Vite dev server in dev, built to static assets in prod.
 */

import "phoenix_html";
import { getHooks } from "live_vue";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "topbar";
import liveVueApp from "../app";
import { initPostHog } from "./utils/posthog";

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: getHooks(liveVueApp),
});

// Progress bar
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", () => topbar.show(300));
window.addEventListener("phx:page-loading-stop", () => topbar.hide());

liveSocket.connect();

window.liveSocket = liveSocket;

// Theme — reads localStorage, applies dark class
function applyTheme() {
  const stored = localStorage.getItem("phx:theme");
  const dark = stored
    ? stored === "dark"
    : window.matchMedia("(prefers-color-scheme: dark)").matches;
  document.documentElement.classList.toggle("dark", dark);
}
applyTheme();
window.addEventListener("storage", (e) => {
  if (e.key === "phx:theme") applyTheme();
});
window.addEventListener("phx:set-theme", applyTheme);

window.addEventListener("phx:set-locale", (event) => {
  const locale = event.detail?.locale;
  if (typeof locale === "string" && locale.length > 0) {
    document.documentElement.lang = locale;
  }
});

initPostHog();

// Native Modals
window.addEventListener("phx:show-modal", (e) => {
  if (e.target.showModal) {
    e.target.showModal();
  }
});
window.addEventListener("phx:hide-modal", (e) => {
  if (e.target.close) {
    e.target.close();
  }
});

// Dev tools
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    reloader.enableServerLogs();

    let keyDown;
    window.addEventListener("keydown", (e) => (keyDown = e.key));
    window.addEventListener("keyup", () => (keyDown = null));
    window.addEventListener(
      "click",
      (e) => {
        if (keyDown === "c") {
          e.preventDefault();
          e.stopImmediatePropagation();
          reloader.openEditorAtCaller(e.target);
        } else if (keyDown === "d") {
          e.preventDefault();
          e.stopImmediatePropagation();
          reloader.openEditorAtDef(e.target);
        }
      },
      true,
    );

    window.liveReloader = reloader;
  });
}

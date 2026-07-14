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
import {
  capturePendingHistoryScroll,
  clearPendingHistoryScroll,
  rememberCurrentHistoryScroll,
} from "../app/shared/navigation/historyScroll";
import { initPostHog } from "./utils/posthog";
import { preloadPublicRouteTargets } from "./utils/preload_public_routes";
import { SeoMetadata } from "./utils/seo_metadata";

if (!window.__storyarnAppInitialized) {
  window.__storyarnAppInitialized = true;

  const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
  // Kept in this page's JS realm so duplicated tabs never inherit the token.
  // LiveView navigation reuses the realm, preserving cross-flow player handoffs.
  const playerTabId =
    crypto.randomUUID?.() ??
    Array.from(crypto.getRandomValues(new Uint32Array(4)), (value) => value.toString(16)).join("-");

  const liveSocket = new LiveSocket("/live", Socket, {
    longPollFallbackMs: 2500,
    params: { _csrf_token: csrfToken, player_tab_id: playerTabId },
    hooks: { ...getHooks(liveVueApp), SeoMetadata },
  });

  // Progress bar
  topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
  window.addEventListener("phx:page-loading-start", () => topbar.show(300));
  window.addEventListener("phx:page-loading-stop", () => {
    topbar.hide();
    preloadPublicRouteTargets();
  });

  // Capture the target history entry before LiveView replaces the current DOM.
  // Async Vue routes can otherwise trigger scroll anchoring and overwrite it.
  window.addEventListener("popstate", (event) => capturePendingHistoryScroll(event.state));
  window.addEventListener("phx:navigate", (event) => {
    if (!event.detail?.pop) clearPendingHistoryScroll();
  });
  window.addEventListener(
    "click",
    (event) => {
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
        return;
      }

      const link = event.target.closest?.(
        'a[data-phx-link="redirect"][data-phx-link-state="push"]',
      );
      if (link) rememberCurrentHistoryScroll();
    },
    true,
  );

  liveSocket.connect();
  preloadPublicRouteTargets();

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
}

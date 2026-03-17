/**
 * Landing page entry point — only loaded on the public landing page.
 * Keeps Three.js + GSAP out of the main app.js bundle.
 *
 * Orchestrates loading: hides page until Three.js scenes are ready,
 * then fades in to avoid showing uninitialized visuals.
 */

import { initSentry } from "./utils/sentry";
initSentry();

// Mark page as loading immediately
const shell = document.querySelector(".landing-shell");
shell?.classList.add("is-loading");

import "./landing_page/portal";
import "./landing_page/scroll_animation";
import "./landing_page/discover_monitor";
import "./landing_page/section_scroll";
import "./landing_page/animations";
import "./landing_page/discover_section";

import { whenPortalReady } from "./landing_page/portal";
import { whenMonitorReady } from "./landing_page/discover_monitor";

// Wait for both Three.js scenes, then reveal
Promise.all([whenPortalReady(), whenMonitorReady()]).then(() => {
  if (shell) {
    shell.classList.remove("is-loading");
    shell.classList.add("is-ready");
  }
});

// Safety timeout: reveal after 4s even if something fails
setTimeout(() => {
  if (shell?.classList.contains("is-loading")) {
    shell.classList.remove("is-loading");
    shell.classList.add("is-ready");
  }
}, 4000);

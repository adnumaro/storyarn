/**
 * Landing page entry point — only loaded on the public landing page.
 * Keeps Three.js + GSAP out of the main app.js bundle.
 *
 * Shows a loading overlay while Three.js scenes initialize,
 * with a minimum 500ms display time to avoid flash.
 */

import { initSentry } from "./utils/sentry";

initSentry();

// ── Loader setup ──
const shell = document.querySelector(".landing-shell");
const loader = document.getElementById("landing-loader");
const loaderFill = loader?.querySelector(".lp-loader-fill");
const loadStart = performance.now();
const MIN_LOAD_MS = 500;

shell?.classList.add("is-loading");

let loadedCount = 0;
const totalSteps = 2; // portal + monitor

function updateProgress() {
  loadedCount++;
  const pct = Math.min(Math.round((loadedCount / totalSteps) * 100), 100);
  if (loaderFill) loaderFill.style.width = `${pct}%`;
}

function revealPage() {
  const elapsed = performance.now() - loadStart;
  const remaining = Math.max(MIN_LOAD_MS - elapsed, 0);

  // Ensure fill bar reaches 100% before dismissing
  if (loaderFill) loaderFill.style.width = "100%";

  setTimeout(() => {
    shell?.classList.remove("is-loading");
    loader?.classList.add("is-done");

    // Remove loader from DOM after fade out
    setTimeout(() => loader?.remove(), 600);
  }, remaining);
}

// ── Load modules ──
import "./landing_page/portal";
import "./landing_page/scroll_animation";
import "./landing_page/discover_monitor";
import "./landing_page/section_scroll";
import "./landing_page/animations";
import "./landing_page/discover_section";

import { whenMonitorReady } from "./landing_page/discover_monitor";
import { whenPortalReady } from "./landing_page/portal";

// Track each scene independently
whenPortalReady().then(updateProgress);
whenMonitorReady().then(updateProgress);

// Reveal when both are ready (respecting minimum time)
Promise.all([whenPortalReady(), whenMonitorReady()]).then(revealPage);

// Safety timeout: reveal after 5s even if something fails
setTimeout(() => {
  if (shell?.classList.contains("is-loading")) {
    revealPage();
  }
}, 5000);

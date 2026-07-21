import { rememberCurrentHistoryScroll } from "./historyScroll";

/**
 * Programmatic LiveView navigation for contexts where rendering an anchor is
 * not possible (palette commands, imperative handlers). Synthesizes a click on
 * a `data-phx-link` anchor so LiveView's window-level handler performs the
 * same navigation a `LiveLink` would — never `window.location`.
 */
export function liveNavigate(
  to: string,
  mode: "navigate" | "patch" = "navigate",
  state: "push" | "replace" = "push",
): void {
  if (mode === "navigate" && state === "push") {
    // Same reason as LiveLink: LiveView only stores truthy scroll positions,
    // so persist the current one explicitly before its click handler runs.
    rememberCurrentHistoryScroll();
  }

  const anchor = document.createElement("a");
  anchor.href = to;
  anchor.setAttribute("data-phx-link", mode === "patch" ? "patch" : "redirect");
  anchor.setAttribute("data-phx-link-state", state);
  anchor.style.display = "none";

  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
}

/**
 * Theme management module.
 * Handles theme toggling and keyboard shortcuts.
 *
 * Theme is stored in localStorage as "phx:theme" = "light" | "dark".
 * When absent, falls back to OS preference via prefers-color-scheme.
 *
 * The theme is applied as data-theme attribute on <html>.
 * daisyUI uses this attribute to switch CSS variables.
 */

const getPreferredTheme = () => {
  const stored = localStorage.getItem("phx:theme");
  if (stored) return stored;
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
};

const applyTheme = () => {
  document.documentElement.setAttribute("data-theme", getPreferredTheme());
};

const setTheme = (theme) => {
  if (theme === "system") {
    localStorage.removeItem("phx:theme");
  } else if (theme === "toggle") {
    const current = document.documentElement.getAttribute("data-theme") || getPreferredTheme();
    const newTheme = current === "dark" ? "light" : "dark";
    localStorage.setItem("phx:theme", newTheme);
  } else {
    localStorage.setItem("phx:theme", theme);
  }
  applyTheme();
};

// Apply theme immediately when this module loads (app.js is deferred,
// so this runs after DOM is ready but before LiveView connects)
applyTheme();

// Re-apply after every LiveView navigation (guards against morphdom stripping data-theme)
window.addEventListener("phx:page-loading-stop", applyTheme);

// Guard against data-theme being removed by morphdom or LiveReloader
new MutationObserver(() => {
  if (!document.documentElement.getAttribute("data-theme")) {
    applyTheme();
  }
}).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });

// Listen for storage changes (sync across tabs)
window.addEventListener("storage", (e) => {
  if (e.key === "phx:theme") {
    setTheme(e.newValue || "system");
  }
});

// Listen for theme toggle events from LiveView
window.addEventListener("phx:set-theme", (e) => {
  setTheme(e.target.dataset.phxTheme);
});

// Global keyboard shortcuts
document.addEventListener("keydown", (e) => {
  // Ignore if typing in an input or textarea
  if (
    e.target.tagName === "INPUT" ||
    e.target.tagName === "TEXTAREA" ||
    e.target.isContentEditable
  ) {
    return;
  }

  // D — Toggle dark/light mode (global, no modifiers)
  // NOTE: This shortcut fires everywhere outside inputs. Be careful adding new
  // bare-letter shortcuts — they conflict with canvas shortcuts (flow E = inline edit).
  if (e.key === "d" && !e.metaKey && !e.ctrlKey && !e.altKey) {
    e.preventDefault();
    setTheme("toggle");
  }
});

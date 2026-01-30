/**
 * Theme management module.
 * Handles theme toggling and keyboard shortcuts.
 */

const getPreferredTheme = () => {
  const stored = localStorage.getItem("phx:theme");
  if (stored) return stored;
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
};

const setTheme = (theme) => {
  if (theme === "system") {
    localStorage.removeItem("phx:theme");
    document.documentElement.setAttribute("data-theme", getPreferredTheme());
  } else if (theme === "toggle") {
    const current = document.documentElement.getAttribute("data-theme") || getPreferredTheme();
    const newTheme = current === "dark" ? "light" : "dark";
    localStorage.setItem("phx:theme", newTheme);
    document.documentElement.setAttribute("data-theme", newTheme);
  } else {
    localStorage.setItem("phx:theme", theme);
    document.documentElement.setAttribute("data-theme", theme);
  }
};

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

  // D - Toggle dark mode
  if (e.key === "d" && !e.metaKey && !e.ctrlKey && !e.altKey) {
    e.preventDefault();
    setTheme("toggle");
  }

  // E - Go to preferences/settings
  if (e.key === "e" && !e.metaKey && !e.ctrlKey && !e.altKey) {
    e.preventDefault();
    window.location.href = "/users/settings";
  }
});

export { setTheme, getPreferredTheme };

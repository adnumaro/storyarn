// Auto-closes the settings sidebar checkbox when resizing to desktop (lg: breakpoint).
// Prevents stale mobile toggle state from affecting the desktop layout.
export const SettingsSidebar = {
  mounted() {
    this.mql = window.matchMedia("(min-width: 768px)");
    this.handler = (e) => {
      if (e.matches) {
        const cb = document.getElementById("settings-sidebar-check");
        if (cb) cb.checked = false;
      }
    };
    this.mql.addEventListener("change", this.handler);
  },

  destroyed() {
    this.mql.removeEventListener("change", this.handler);
  },
};

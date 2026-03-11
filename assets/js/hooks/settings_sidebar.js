// Auto-closes the sidebar checkbox when resizing to desktop (md: breakpoint).
// Prevents stale mobile toggle state from affecting the desktop layout.
// Used by both settings layout and app layout.
export const SettingsSidebar = {
  mounted() {
    this.mql = window.matchMedia("(min-width: 768px)");
    this.handler = (e) => {
      if (e.matches) {
        for (const id of ["settings-sidebar-check", "app-sidebar-check"]) {
          const cb = document.getElementById(id);
          if (cb) cb.checked = false;
        }
      }
    };
    this.mql.addEventListener("change", this.handler);
  },

  destroyed() {
    this.mql.removeEventListener("change", this.handler);
  },
};

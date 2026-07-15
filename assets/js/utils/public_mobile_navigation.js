const desktopNavigationQuery = "(min-width: 80rem)";

function closeOpenNavigation(hook) {
  if (hook.el.getAttribute("aria-hidden") !== "false") return false;

  const closeCommand = hook.el.getAttribute("data-close");
  if (!closeCommand) return false;

  hook.js().exec(closeCommand);
  return true;
}

export const PublicMobileNavigation = {
  mounted() {
    this.desktopMediaQuery = window.matchMedia(desktopNavigationQuery);
    this.handleDesktopViewport = (mediaQuery) => {
      if (mediaQuery.matches) closeOpenNavigation(this);
    };
    this.handleKeydown = (event) => {
      if (event.key === "Escape" && closeOpenNavigation(this)) event.preventDefault();
    };
    this.desktopMediaQuery.addEventListener("change", this.handleDesktopViewport);
    window.addEventListener("keydown", this.handleKeydown);
    this.handleDesktopViewport(this.desktopMediaQuery);
  },
  updated() {
    this.handleDesktopViewport(this.desktopMediaQuery);
  },
  destroyed() {
    closeOpenNavigation(this);
    this.desktopMediaQuery.removeEventListener("change", this.handleDesktopViewport);
    window.removeEventListener("keydown", this.handleKeydown);
  },
};

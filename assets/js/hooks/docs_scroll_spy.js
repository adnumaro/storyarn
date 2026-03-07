/**
 * DocsScrollSpy — highlights the active TOC link based on scroll position.
 * Attached to the <main> scroll container in the docs layout.
 */
const DocsScrollSpy = {
  mounted() {
    this._clickedId = null;
    this.setup();
  },

  updated() {
    this.cleanup();
    this.setup();
  },

  destroyed() {
    this.cleanup();
  },

  setup() {
    const headings = Array.from(this.el.querySelectorAll("h2[id], h3[id]"));
    if (!headings.length) return;

    const tocLinks = document.querySelectorAll("#docs-toc [data-toc-id]");
    if (!tocLinks.length) return;

    const ACTIVE = ["text-primary", "font-medium"];
    const INACTIVE = ["text-base-content/50"];

    const setActive = (id) => {
      tocLinks.forEach((link) => {
        const isActive = link.dataset.tocId === id;
        for (const c of ACTIVE) link.classList.toggle(c, isActive);
        for (const c of INACTIVE) link.classList.toggle(c, !isActive);
      });
      history.replaceState(null, "", `#${id}`);
    };

    // On scroll: find the last heading that scrolled past the top of the container.
    // If user clicked a TOC link, keep that active until they scroll manually.
    const OFFSET = 80;

    this._onScroll = () => {
      // If a click just happened, clear it after scroll settles
      if (this._clickedId) return;

      const containerTop = this.el.getBoundingClientRect().top;
      let current = null;

      for (const h of headings) {
        const top = h.getBoundingClientRect().top - containerTop;
        if (top <= OFFSET) {
          current = h.id;
        } else {
          break;
        }
      }

      // If scrolled to the bottom, activate the last heading
      if (this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 2) {
        current = headings[headings.length - 1].id;
      }

      if (current) setActive(current);
    };

    this.el.addEventListener("scroll", this._onScroll, { passive: true });
    // Initial highlight
    this._onScroll();

    // TOC click: smooth scroll + force-activate that item
    this._handleClick = (e) => {
      const link = e.target.closest("[data-toc-id]");
      if (!link) return;
      e.preventDefault();

      const id = link.dataset.tocId;
      const target = document.getElementById(id);
      if (!target) return;

      // Force-activate immediately, block scroll handler temporarily
      this._clickedId = id;
      setActive(id);
      target.scrollIntoView({ behavior: "smooth", block: "start" });

      // Release after scroll finishes (~500ms is enough for smooth scroll)
      clearTimeout(this._clickTimer);
      this._clickTimer = setTimeout(() => {
        this._clickedId = null;
      }, 600);
    };

    const toc = document.getElementById("docs-toc");
    if (toc) toc.addEventListener("click", this._handleClick);
  },

  cleanup() {
    if (this._onScroll) {
      this.el.removeEventListener("scroll", this._onScroll);
    }
    clearTimeout(this._clickTimer);
    const toc = document.getElementById("docs-toc");
    if (toc && this._handleClick) {
      toc.removeEventListener("click", this._handleClick);
    }
  },
};

export { DocsScrollSpy };

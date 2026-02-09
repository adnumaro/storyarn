/**
 * SlashCommand — Phoenix LiveView Hook for the slash command menu.
 *
 * Handles positioning, keyboard navigation (arrows, Enter, Escape),
 * search filtering, and mouse interaction.
 */

export const SlashCommand = {
  mounted() {
    this.searchInput = this.el.querySelector("#slash-menu-search-input");
    this.list = this.el.querySelector("#slash-menu-list");
    this.items = Array.from(this.el.querySelectorAll(".slash-menu-item"));
    this.highlightedIndex = 0;

    this.handleKeyDown = this.handleKeyDown.bind(this);
    this.handleSearchInput = this.handleSearchInput.bind(this);
    this.handleItemMouseEnter = this.handleItemMouseEnter.bind(this);

    document.addEventListener("keydown", this.handleKeyDown);

    if (this.searchInput) {
      this.searchInput.addEventListener("input", this.handleSearchInput);
    }

    this.items.forEach((item) => {
      item.addEventListener("mouseenter", this.handleItemMouseEnter);
    });

    this.positionMenu();
    this.updateHighlight();

    // Focus search input after a tick (allow DOM to settle)
    requestAnimationFrame(() => {
      if (this.searchInput) this.searchInput.focus();
    });
  },

  positionMenu() {
    const targetId = this.el.dataset.targetId;
    const target = document.getElementById(targetId);
    if (!target) return;

    const rect = target.getBoundingClientRect();
    const menuHeight = this.el.offsetHeight || 360;
    const viewportHeight = window.innerHeight;

    // Position below the target element, aligned left
    let top = rect.bottom + 4;
    let left = rect.left;

    // Flip above if overflowing viewport bottom
    if (top + menuHeight > viewportHeight - 16) {
      top = rect.top - menuHeight - 4;
    }

    // Clamp left to keep menu in viewport
    const menuWidth = this.el.offsetWidth || 280;
    if (left + menuWidth > window.innerWidth - 16) {
      left = window.innerWidth - menuWidth - 16;
    }
    if (left < 16) left = 16;

    this.el.style.position = "fixed";
    this.el.style.top = `${top}px`;
    this.el.style.left = `${left}px`;
  },

  visibleItems() {
    return this.items.filter((item) => !item.hidden);
  },

  handleKeyDown(event) {
    const visible = this.visibleItems();
    if (visible.length === 0 && event.key !== "Escape") return;

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        this.highlightedIndex =
          (this.highlightedIndex + 1) % visible.length;
        this.updateHighlight();
        break;

      case "ArrowUp":
        event.preventDefault();
        this.highlightedIndex =
          (this.highlightedIndex - 1 + visible.length) % visible.length;
        this.updateHighlight();
        break;

      case "Enter":
        event.preventDefault();
        if (visible[this.highlightedIndex]) {
          const type = visible[this.highlightedIndex].dataset.type;
          this.pushEvent("select_slash_command", { type });
        }
        break;

      case "Escape":
        event.preventDefault();
        this.pushEvent("close_slash_menu");
        break;
    }
  },

  handleSearchInput() {
    const query = (this.searchInput.value || "").toLowerCase().trim();

    this.items.forEach((item) => {
      const label = (item.dataset.label || "").toLowerCase();
      item.hidden = query !== "" && !label.includes(query);
    });

    // Hide empty groups
    const groups = this.el.querySelectorAll(".slash-menu-group");
    groups.forEach((group) => {
      const visibleInGroup = group.querySelectorAll(
        ".slash-menu-item:not([hidden])",
      );
      group.hidden = visibleInGroup.length === 0;
    });

    // Reset highlight to first visible
    this.highlightedIndex = 0;
    this.updateHighlight();
  },

  handleItemMouseEnter(event) {
    const visible = this.visibleItems();
    const idx = visible.indexOf(event.currentTarget);
    if (idx >= 0) {
      this.highlightedIndex = idx;
      this.updateHighlight();
    }
  },

  updateHighlight() {
    const visible = this.visibleItems();
    this.items.forEach((item) => item.classList.remove("highlighted"));
    if (visible[this.highlightedIndex]) {
      visible[this.highlightedIndex].classList.add("highlighted");
      visible[this.highlightedIndex].scrollIntoView({ block: "nearest" });
    }
  },

  destroyed() {
    document.removeEventListener("keydown", this.handleKeyDown);

    if (this.searchInput) {
      this.searchInput.removeEventListener("input", this.handleSearchInput);
    }

    this.items.forEach((item) => {
      item.removeEventListener("mouseenter", this.handleItemMouseEnter);
    });
  },
};

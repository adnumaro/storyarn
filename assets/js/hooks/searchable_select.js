/**
 * SearchableSelect — LiveView hook for a searchable dropdown.
 *
 * Renders a popover with a search input and a list of server-rendered options.
 * Filtering is done client-side (hide/show via `display:none`) — zero round-trips.
 * Closes automatically when an option is clicked (via event delegation on the list).
 *
 * Expected DOM structure (set by the HEEx component):
 *   <div phx-hook="SearchableSelect" id="...">
 *     <button data-role="trigger">...</button>
 *     <div data-role="popover" style="display:none">
 *       <input data-role="search" />
 *       <div data-role="list">
 *         <button data-search-text="..." phx-click="...">label</button>
 *       </div>
 *       <div data-role="empty">No matches</div>
 *     </div>
 *   </div>
 */
export const SearchableSelect = {
  mounted() {
    this.setup();
  },

  updated() {
    // Re-bind after LiveView patches the DOM (e.g., options list changes)
    this.setup();
  },

  setup() {
    const newTrigger = this.el.querySelector('[data-role="trigger"]');
    this.popover = this.el.querySelector('[data-role="popover"]');
    const newSearch = this.el.querySelector('[data-role="search"]');
    this.list = this.el.querySelector('[data-role="list"]');
    this.empty = this.el.querySelector('[data-role="empty"]');

    if (!newTrigger || !this.popover || !newSearch || !this.list) return;

    // Skip re-binding if DOM elements haven't changed
    if (this._bound && newTrigger === this.trigger && newSearch === this.search) return;

    // Tear down old listeners before re-binding
    this._teardownLocal();

    this.trigger = newTrigger;
    this.search = newSearch;
    this._bound = true;
    this.isOpen = false;

    // Toggle on trigger click
    this._onTriggerClick = (e) => {
      e.stopPropagation();
      this.isOpen ? this.close() : this.open();
    };
    this.trigger.addEventListener("click", this._onTriggerClick);

    // Filter on input — server-side or client-side
    this.serverSearchEvent = this.el.dataset.serverSearch || null;
    if (this.serverSearchEvent) {
      this._debounceTimer = null;
      this._onSearchInput = () => {
        clearTimeout(this._debounceTimer);
        this._debounceTimer = setTimeout(() => {
          this.pushEvent(this.serverSearchEvent, { query: this.search.value || "" });
        }, 300);
      };
    } else {
      this._onSearchInput = () => this.filter();
    }
    this.search.addEventListener("input", this._onSearchInput);

    // Close when an option is clicked (event delegation)
    this._onListClick = () => {
      requestAnimationFrame(() => this.close());
    };
    this.list.addEventListener("click", this._onListClick);

    // Close on outside click
    if (!this._outsideClick) {
      this._outsideClick = (e) => {
        if (this.isOpen && !this.el.contains(e.target)) {
          this.close();
        }
      };
      document.addEventListener("mousedown", this._outsideClick);
    }

    // Keyboard
    this._onSearchKeydown = (e) => {
      if (e.key === "Escape") {
        e.preventDefault();
        e.stopPropagation();
        this.close();
      }
    };
    this.search.addEventListener("keydown", this._onSearchKeydown);
  },

  _teardownLocal() {
    if (this._debounceTimer) clearTimeout(this._debounceTimer);
    if (this.trigger && this._onTriggerClick) {
      this.trigger.removeEventListener("click", this._onTriggerClick);
    }
    if (this.search) {
      if (this._onSearchInput) this.search.removeEventListener("input", this._onSearchInput);
      if (this._onSearchKeydown) this.search.removeEventListener("keydown", this._onSearchKeydown);
    }
    if (this.list && this._onListClick) {
      this.list.removeEventListener("click", this._onListClick);
    }
  },

  open() {
    this.isOpen = true;
    this.popover.style.display = "block";
    this.search.value = "";
    this.filter();
    requestAnimationFrame(() => this.search.focus());
  },

  close() {
    this.isOpen = false;
    this.popover.style.display = "none";
  },

  filter() {
    const q = (this.search.value || "").toLowerCase().trim();
    const items = this.list.querySelectorAll("[data-search-text]");
    let visible = 0;

    items.forEach((item) => {
      const text = item.dataset.searchText || "";
      const match = !q || text.includes(q);
      item.style.display = match ? "" : "none";
      if (match) visible++;
    });

    // Hide "Show more" during client-side filtering with a query
    const loadMore = this.list.querySelector('[data-role="load-more"]');
    if (loadMore) loadMore.style.display = q ? "none" : "";

    if (this.empty) {
      this.empty.style.display = visible === 0 ? "" : "none";
    }
  },

  destroyed() {
    this._teardownLocal();
    if (this._outsideClick) {
      document.removeEventListener("mousedown", this._outsideClick);
    }
  },
};

/**
 * SearchableSelect — LiveView hook for a searchable dropdown.
 *
 * Uses shared floating_popover utility (@floating-ui/dom + body append)
 * so the dropdown escapes overflow:hidden/clip containers.
 *
 * Renders a popover with a search input and a list of server-rendered options.
 * Filtering is done client-side (hide/show via `display:none`) — zero round-trips.
 * Closes automatically when an option is clicked (via event delegation on the list).
 *
 * Expected DOM structure (set by the HEEx component):
 *   <div phx-hook="SearchableSelect" id="...">
 *     <button data-role="trigger">...</button>
 *     <template data-role="popover-template">
 *       <input data-role="search" />
 *       <div data-role="list">
 *         <button data-search-text="..." phx-click="...">label</button>
 *       </div>
 *       <div data-role="empty">No matches</div>
 *     </template>
 *   </div>
 */
import { createFloatingPopover } from "../utils/floating_popover";

export const SearchableSelect = {
  mounted() {
    this.setup();
  },

  updated() {
    // Options may have changed — rebuild popover content
    const wasOpen = this._fp?.isOpen;
    const prevSearch = this.search?.value || "";
    this._destroyPopover();
    this.setup();
    if (wasOpen && this._fp) {
      this._fp.open();
      this._onOpen();
      this.search.value = prevSearch;
      if (!this.serverSearchEvent) {
        this.filter();
      }
    }
  },

  setup() {
    this.trigger = this.el.querySelector('[data-role="trigger"]');
    this.template = this.el.querySelector('[data-role="popover-template"]');

    if (!this.trigger || !this.template) return;

    // Create floating popover (appended to body)
    this._fp = createFloatingPopover(this.trigger, {
      class: "bg-base-100 border border-base-300 rounded-lg shadow-lg",
      width: "14rem",
    });

    // Clone template content into the floating container
    const content = this.template.content.cloneNode(true);
    this._fp.el.appendChild(content);

    // Query inside the floating container
    this.search = this._fp.el.querySelector('[data-role="search"]');
    this.list = this._fp.el.querySelector('[data-role="list"]');
    this.empty = this._fp.el.querySelector('[data-role="empty"]');

    // Toggle on trigger click
    this._onTriggerClick = (e) => {
      e.stopPropagation();
      if (this._fp.isOpen) {
        this._fp.close();
      } else {
        this._fp.open();
        this._onOpen();
      }
    };
    this.trigger.addEventListener("click", this._onTriggerClick);

    // Filter on input — server-side or client-side
    this.serverSearchEvent = this.el.dataset.serverSearch || null;
    if (this.search) {
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
    }

    // Option clicks — re-push events from hook (elements are outside LiveView DOM tree)
    if (this.list) {
      this._onListClick = (e) => {
        const btn = e.target.closest("[data-event]");
        if (!btn) return;

        const event = btn.dataset.event;
        let payload = {};
        if (btn.dataset.params) {
          try {
            payload = JSON.parse(btn.dataset.params);
          } catch {
            /* no params */
          }
        }

        this.pushEvent(event, payload);
        if (btn.dataset.role !== "load-more") {
          requestAnimationFrame(() => this._fp.close());
        }
      };
      this.list.addEventListener("click", this._onListClick);
    }

    // Deep-search toggle: re-push the phx-click event
    const deepToggle = this._fp.el.querySelector('[data-role="deep-search-toggle"]');
    if (deepToggle) {
      this._onDeepToggleClick = () => {
        const event = deepToggle.dataset.event;
        if (event) this.pushEvent(event, {});
      };
      deepToggle.addEventListener("change", this._onDeepToggleClick);
    }
  },

  _onOpen() {
    if (this.search) {
      this.search.value = "";
      this.filter();
      requestAnimationFrame(() => this.search.focus());
    }
  },

  _destroyPopover() {
    if (this._debounceTimer) clearTimeout(this._debounceTimer);
    if (this.trigger && this._onTriggerClick) {
      this.trigger.removeEventListener("click", this._onTriggerClick);
    }
    if (this.search && this._onSearchInput) {
      this.search.removeEventListener("input", this._onSearchInput);
    }
    if (this.list && this._onListClick) {
      this.list.removeEventListener("click", this._onListClick);
    }
    const deepToggle = this._fp?.el?.querySelector('[data-role="deep-search-toggle"]');
    if (deepToggle && this._onDeepToggleClick) {
      deepToggle.removeEventListener("change", this._onDeepToggleClick);
    }
    this._fp?.destroy();
    this._fp = null;
  },

  filter() {
    if (!this.list) return;
    const q = (this.search?.value || "").toLowerCase().trim();
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
    this._destroyPopover();
  },
};

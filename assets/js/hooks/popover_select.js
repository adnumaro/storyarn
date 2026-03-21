/**
 * PopoverSelect — Unified LiveView hook for all searchable select popovers.
 *
 * Consolidates EntitySelect, SearchableSelect, BlockSelect, ReferenceSelect,
 * and TableCellSelect into a single hook with configurable behavior.
 *
 * Features:
 *   - Body-appended floating popover (escapes overflow:hidden containers)
 *   - Client-side filtering (data-search-mode="client")
 *   - Server-side search with debounce (data-search-mode="server")
 *   - Single select (closes on pick) or multi-select (stays open)
 *   - Add-input for creating new options
 *   - Active state highlighting via data-selected + data-active-class
 *   - Infinite scroll via IntersectionObserver
 *   - Dual event routing: internal events → component, selection → parent
 *
 * Data attributes on the hook element:
 *   data-phx-target        — internal event target (SearchableSelect component)
 *   data-select-target     — selection event target (parent CID or CSS selector)
 *   data-select-event      — selection event name (default: "select")
 *   data-search-mode       — "client" (default) or "server"
 *   data-mode              — "single" (default) or "multi"
 *   data-selected          — current value(s), comma-separated for multi
 *   data-active-class      — CSS classes toggled on active items
 *   data-match-trigger-width — if present, popover matches trigger width (min 224px)
 *
 * Roles inside the source div (data-role="popover-source"):
 *   data-role="trigger"        — click toggles popover
 *   data-role="popover-source" — hidden div, content cloned to popover
 *   data-role="search"         — filter/search input
 *   data-role="list"           — scrollable item container
 *   data-role="sentinel"       — infinite scroll trigger
 *   data-role="empty"          — no results message
 *   data-role="add-input"      — create-new input
 *
 * Item attributes:
 *   data-role="option"    — marks a selectable item (click → _pushSelect)
 *   data-params            — JSON payload for selection event
 *   data-value             — item value (for active state matching)
 *   data-search-text       — lowercase text for client-side filtering
 */
import { createFloatingPopover } from "../utils/floating_popover";

export const PopoverSelect = {
  mounted() {
    this._createPopover();
  },

  updated() {
    if (!this._fp) {
      this._createPopover();
      return;
    }
    this._syncContent();
  },

  _createPopover() {
    this.trigger = this.el.querySelector('[data-role="trigger"]');
    if (!this.trigger) return;

    this.mode = this.el.dataset.mode || "single";
    this.searchMode = this.el.dataset.searchMode || "client";
    this._matchWidth = this.el.hasAttribute("data-match-trigger-width");

    // Defer getBoundingClientRect() to open time — avoids forced reflow during mount
    this._fp = createFloatingPopover(this.trigger, {
      class: "bg-base-100 border border-base-content/20 rounded-lg shadow-lg",
      width: "14rem",
    });

    this._loading = false;
    this._prevSearch = "";
    this._syncContent();

    this._onTriggerClick = (e) => {
      e.stopPropagation();

      // Respect disabled state
      if (this.trigger.disabled || this.trigger.hasAttribute("disabled")) return;

      if (this._fp.isOpen) {
        this._fp.close();
      } else {
        this._fp.open();
        this._onOpen();
      }
    };
    this.trigger.addEventListener("click", this._onTriggerClick);
  },

  /** Clone source div content into the floating popover, preserving scroll */
  _syncContent() {
    const source = this.el.querySelector('[data-role="popover-source"]');
    if (!source || !this._fp) return;

    // Skip expensive DOM cloning if the popover is closed — sync on next open
    if (!this._fp.isOpen) {
      this._stale = true;
      return;
    }

    const prevScroll = this.list?.scrollTop || 0;
    const wasOpen = this._fp.isOpen;

    this._unbindPopoverListeners();

    // Replace popover content with a fresh clone of the source
    this._fp.el.innerHTML = "";
    for (const child of source.children) {
      this._fp.el.appendChild(child.cloneNode(true));
    }

    // Re-query elements inside the popover
    this.search = this._fp.el.querySelector('[data-role="search"]');
    this.list = this._fp.el.querySelector('[data-role="list"]');
    this.empty = this._fp.el.querySelector('[data-role="empty"]');
    this.addInput = this._fp.el.querySelector('[data-role="add-input"]');

    this._applyActiveState();
    this._bindPopoverListeners();

    // Restore state if popover was open
    if (wasOpen) {
      if (this.search && this._prevSearch) {
        this.search.value = this._prevSearch;
      }
      if (this.list) {
        this.list.scrollTop = prevScroll;
      }
      // Re-apply client filter if there was a search query
      if (this.searchMode === "client" && this._prevSearch) {
        this._filterClient();
      }
      if (this.search) {
        requestAnimationFrame(() => this.search?.focus());
      }
      requestAnimationFrame(() => {
        this._loading = false;
        this._setupObserver();
      });
    }
  },

  _onOpen() {
    // Sync content if it was deferred while popover was closed
    if (this._stale) {
      this._stale = false;
      this._syncContent();
    }

    // Measure trigger width on demand (deferred from mount to avoid forced reflow)
    if (this._matchWidth && this._fp) {
      const width = `${Math.max(Math.round(this.trigger.getBoundingClientRect().width), 224)}px`;
      this._fp.el.style.width = width;
    }

    this._prevSearch = "";
    if (this.search) {
      this.search.value = "";
      requestAnimationFrame(() => this.search?.focus());
    }
    if (this.searchMode === "client") {
      this._filterClient();
    }
    requestAnimationFrame(() => this._setupObserver());
  },

  _bindPopoverListeners() {
    // Search input
    if (this.search) {
      this._debounceTimer = null;

      if (this.searchMode === "server") {
        this._onSearchInput = () => {
          this._prevSearch = this.search.value;
          clearTimeout(this._debounceTimer);
          this._debounceTimer = setTimeout(() => {
            this._pushInternal("search", { query: this.search.value || "" });
          }, 300);
        };
      } else {
        this._onSearchInput = () => {
          this._prevSearch = this.search.value;
          this._filterClient();
        };
      }
      this.search.addEventListener("input", this._onSearchInput);

      // Prevent keyboard shortcuts (delete, backspace, etc.) from reaching canvas
      this._onSearchKeydown = (e) => {
        e.stopPropagation();
        e.stopImmediatePropagation();
      };
      this.search.addEventListener("keydown", this._onSearchKeydown, true);
    }

    // List clicks
    if (this.list) {
      this._onListClick = (e) => {
        // Option clicks → push to parent
        const option = e.target.closest('[data-role="option"]');
        if (option) {
          let payload = {};
          try {
            payload = JSON.parse(option.dataset.params || "{}");
          } catch {
            /* invalid JSON */
          }
          this._pushSelect(payload);
          if (this.mode === "single") {
            // Optimistic UI: update trigger text immediately without waiting for server
            const label = option.textContent.trim();
            const triggerText = this.trigger?.querySelector("span");
            if (triggerText && label) {
              triggerText.textContent = label;
              triggerText.classList.remove("opacity-50");
            }
            requestAnimationFrame(() => this._fp.close());
          }
          return;
        }

        // Backward compat: buttons with data-event (used by some legacy patterns)
        const eventBtn = e.target.closest("[data-event]");
        if (eventBtn) {
          const event = eventBtn.dataset.event;
          let payload = {};
          try {
            payload = JSON.parse(eventBtn.dataset.params || "{}");
          } catch {
            /* invalid JSON */
          }
          this._pushInternal(event, payload);
          if (this.mode === "single" && eventBtn.dataset.role !== "load-more") {
            requestAnimationFrame(() => this._fp.close());
          }
        }
      };
      this.list.addEventListener("click", this._onListClick);
    }

    // Add-input: push create event on Enter
    if (this.addInput) {
      this._onAddKeydown = (e) => {
        // Prevent keyboard shortcuts from reaching parent
        e.stopPropagation();
        e.stopImmediatePropagation();

        if (e.key !== "Enter") return;
        e.preventDefault();
        const value = this.addInput.value.trim();
        if (!value) return;

        this._pushSelect({ value, action: "create" });
        requestAnimationFrame(() => {
          if (this.addInput) this.addInput.value = "";
        });
      };
      this.addInput.addEventListener("keydown", this._onAddKeydown);
    }
  },

  _unbindPopoverListeners() {
    if (this._debounceTimer) clearTimeout(this._debounceTimer);
    if (this.search && this._onSearchInput) {
      this.search.removeEventListener("input", this._onSearchInput);
    }
    if (this.search && this._onSearchKeydown) {
      this.search.removeEventListener("keydown", this._onSearchKeydown);
    }
    if (this.list && this._onListClick) {
      this.list.removeEventListener("click", this._onListClick);
    }
    if (this.addInput && this._onAddKeydown) {
      this.addInput.removeEventListener("keydown", this._onAddKeydown);
    }
    if (this._observer) {
      this._observer.disconnect();
      this._observer = null;
    }
  },

  /** Push event to the SearchableSelect component (search, load_more) */
  _pushInternal(event, payload) {
    const target = this.el.dataset.phxTarget;
    if (target) {
      this.pushEventTo(target, event, payload);
    } else {
      this.pushEvent(event, payload);
    }
  },

  /** Push selection event to the parent (LiveView or LiveComponent) */
  _pushSelect(payload) {
    const target = this.el.dataset.selectTarget;
    const event = this.el.dataset.selectEvent || "select";
    if (target) {
      const resolved = /^\d+$/.test(target) ? parseInt(target) : target;
      this.pushEventTo(resolved, event, payload);
    } else {
      this.pushEvent(event, payload);
    }
  },

  /** Client-side filtering: show/hide items by data-search-text */
  _filterClient() {
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

    if (this.empty) {
      this.empty.style.display = visible === 0 ? "" : "none";
    }
  },

  /** Apply active CSS classes based on data-selected */
  _applyActiveState() {
    const selected = this.el.dataset.selected;
    if (selected === undefined || !this._fp) return;

    const activeClasses = (this.el.dataset.activeClass || "")
      .split(" ")
      .filter(Boolean);
    if (!activeClasses.length) return;

    const selectedValues = selected.split(",").filter(Boolean);
    const buttons = this._fp.el.querySelectorAll("[data-value]");
    buttons.forEach((btn) => {
      const isActive = selectedValues.includes(btn.dataset.value);
      activeClasses.forEach((cls) => btn.classList.toggle(cls, isActive));
    });
  },

  /** Set up IntersectionObserver for infinite scroll */
  _setupObserver() {
    if (this._observer) {
      this._observer.disconnect();
      this._observer = null;
    }

    const sentinel = this._fp?.el?.querySelector('[data-role="sentinel"]');
    if (!sentinel || !this.list) return;

    this._observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && !this._loading && this._fp?.isOpen) {
          this._loading = true;
          this._pushInternal("load_more", {});
        }
      },
      { root: this.list, threshold: 0.1 },
    );
    this._observer.observe(sentinel);
  },

  destroyed() {
    this._unbindPopoverListeners();
    if (this.trigger && this._onTriggerClick) {
      this.trigger.removeEventListener("click", this._onTriggerClick);
    }
    this._fp?.destroy();
    this._fp = null;
  },
};

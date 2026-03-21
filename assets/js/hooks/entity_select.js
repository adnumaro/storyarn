/**
 * EntitySelect — LiveView hook for entity selector popovers (sheets, flows, scenes).
 *
 * Designed for LiveComponent usage: routes events via `pushEventTo(@myself)`.
 * Features server-side search (debounced), infinite scroll via IntersectionObserver,
 * and active-state highlighting.
 *
 * Uses a hidden source div (patched by LiveView) whose content is cloned into
 * a body-appended floating popover (escapes overflow:hidden containers).
 *
 * Expected DOM structure:
 *   <div phx-hook="EntitySelect" id="..." data-phx-target="..."
 *        data-selected="..." data-active-class="..." data-version="...">
 *     <button data-role="trigger">...</button>
 *     <div data-role="popover-source" style="display:none">
 *       <input data-role="search" />
 *       <div data-role="list">...</div>
 *       <div data-role="empty">...</div>
 *     </div>
 *   </div>
 */
import { createFloatingPopover } from "../utils/floating_popover";

export const EntitySelect = {
  mounted() {
    this._createPopover();
  },

  updated() {
    if (!this._fp) {
      this._createPopover();
      return;
    }

    // Sync popover content from the LiveView-patched source div
    this._syncContent();
  },

  _createPopover() {
    this.trigger = this.el.querySelector('[data-role="trigger"]');
    this.target = this.el.dataset.phxTarget || null;

    if (!this.trigger) return;

    this._fp = createFloatingPopover(this.trigger, {
      class: "bg-base-100 border border-base-content/20 rounded-lg shadow-lg",
      width: "14rem",
    });

    this._loading = false;
    this._prevSearch = "";
    this._syncContent();

    this._onTriggerClick = (e) => {
      e.stopPropagation();
      if (this._fp.isOpen) {
        this._fp.close();
      } else {
        this._fp.open();
        this._prevSearch = "";
        if (this.search) {
          this.search.value = "";
          requestAnimationFrame(() => this.search.focus());
        }
        requestAnimationFrame(() => this._setupObserver());
      }
    };
    this.trigger.addEventListener("click", this._onTriggerClick);
  },

  /** Clone source div content into the floating popover, preserving scroll */
  _syncContent() {
    const source = this.el.querySelector('[data-role="popover-source"]');
    if (!source || !this._fp) return;

    const prevScroll = this.list?.scrollTop || 0;
    const wasOpen = this._fp.isOpen;

    // Unbind old listeners
    this._unbindPopoverListeners();

    // Replace popover content with a fresh clone of the source
    this._fp.el.innerHTML = "";
    for (const child of source.children) {
      this._fp.el.appendChild(child.cloneNode(true));
    }

    // Re-query elements
    this.search = this._fp.el.querySelector('[data-role="search"]');
    this.list = this._fp.el.querySelector('[data-role="list"]');
    this.empty = this._fp.el.querySelector('[data-role="empty"]');

    this._applyActiveState();
    this._bindPopoverListeners();

    // Restore state
    if (wasOpen) {
      if (this.search && this._prevSearch) {
        this.search.value = this._prevSearch;
      }
      if (this.list) {
        this.list.scrollTop = prevScroll;
      }
      // Re-focus search after DOM replacement
      if (this.search) {
        requestAnimationFrame(() => this.search.focus());
      }
      requestAnimationFrame(() => {
        this._loading = false;
        this._setupObserver();
      });
    }
  },

  _bindPopoverListeners() {
    if (this.search) {
      this._debounceTimer = null;
      this._onSearchInput = () => {
        this._prevSearch = this.search.value;
        clearTimeout(this._debounceTimer);
        this._debounceTimer = setTimeout(() => {
          this._push("search_entities", { query: this.search.value || "" });
        }, 300);
      };
      this.search.addEventListener("input", this._onSearchInput);

      // Prevent keyboard shortcuts (delete, backspace, etc.) from reaching canvas
      this._onSearchKeydown = (e) => {
        e.stopPropagation();
        e.stopImmediatePropagation();
      };
      this.search.addEventListener("keydown", this._onSearchKeydown, true);
    }

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

        this._push(event, payload);
        requestAnimationFrame(() => this._fp.close());
      };
      this.list.addEventListener("click", this._onListClick);
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
    if (this._observer) {
      this._observer.disconnect();
      this._observer = null;
    }
  },

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
          this._push("load_more", {});
        }
      },
      { root: this.list, threshold: 0.1 },
    );
    this._observer.observe(sentinel);
  },

  _push(event, payload) {
    if (this.target) {
      this.pushEventTo(this.target, event, payload);
    } else {
      this.pushEvent(event, payload);
    }
  },

  _applyActiveState() {
    const selected = this.el.dataset.selected;
    if (selected === undefined || !this._fp) return;

    const activeClasses = (this.el.dataset.activeClass || "")
      .split(" ")
      .filter(Boolean);
    if (!activeClasses.length) return;

    const buttons = this._fp.el.querySelectorAll("[data-value]");
    buttons.forEach((btn) => {
      const isActive = btn.dataset.value === selected;
      activeClasses.forEach((cls) => btn.classList.toggle(cls, isActive));
    });
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

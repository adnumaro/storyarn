/**
 * BlockSelect — LiveView hook for select & multi-select sheet blocks.
 *
 * Handles both modes via `data-mode="select"|"multi_select"`:
 *   - select: click option → push event → close popover
 *   - multi_select: click option → push event → popover stays open
 *
 * Uses shared floating_popover utility (@floating-ui/dom + body append)
 * so the dropdown escapes overflow:hidden/clip containers and survives
 * LiveView re-renders without flash-closing.
 *
 * Expected DOM structure (server-rendered):
 *   <div phx-hook="BlockSelect" id="..." data-mode="select|multi_select"
 *        data-phx-target="..." >
 *     <button data-role="trigger">...</button>
 *     <template data-role="popover-template">
 *       <input data-role="search" />
 *       <div data-role="list">
 *         <button data-event="..." data-params='{"id":"...","value":"..."}' data-search-text="...">
 *           label
 *         </button>
 *       </div>
 *       <input data-role="add-input" />
 *       <div data-role="empty">No matches</div>
 *     </template>
 *   </div>
 */
import { createFloatingPopover } from "../utils/floating_popover";

export const BlockSelect = {
  mounted() {
    this.setup();
  },

  updated() {
    // Skip expensive destroy+recreate if popover is closed — rebuild on next open
    if (!this._fp?.isOpen) {
      this._stale = true;
      return;
    }

    const prevSearch = this.search?.value || "";
    this._destroyPopover();
    this.setup();
    this._fp.open();
    if (this.search) {
      this.search.value = prevSearch;
      this.filter();
    }
  },

  setup() {
    this.trigger = this.el.querySelector('[data-role="trigger"]');
    this.template = this.el.querySelector('[data-role="popover-template"]');
    this.mode = this.el.dataset.mode || "select";
    this.target = this.el.dataset.phxTarget || null;

    if (!this.trigger || !this.template) return;

    // Defer getBoundingClientRect() to open time — avoids forced reflow during mount
    this._fp = createFloatingPopover(this.trigger, {
      class: "bg-base-200 border border-base-content/20 rounded-lg shadow-lg",
      width: "14rem",
    });
    this._needsWidthMeasure = true;

    const content = this.template.content.cloneNode(true);
    this._fp.el.appendChild(content);

    // LiveView doesn't patch <template> content (DocumentFragment),
    // so active-state classes baked into the template become stale.
    // Re-apply based on data-selected (which IS patched as an attribute).
    this._applyActiveState();

    this.search = this._fp.el.querySelector('[data-role="search"]');
    this.list = this._fp.el.querySelector('[data-role="list"]');
    this.empty = this._fp.el.querySelector('[data-role="empty"]');
    this.addInput = this._fp.el.querySelector('[data-role="add-input"]');

    // Trigger click toggles popover
    this._onTriggerClick = (e) => {
      e.stopPropagation();
      if (this._fp.isOpen) {
        this._fp.close();
      } else {
        // Rebuild if content changed while closed
        if (this._stale) {
          this._stale = false;
          const prevSearch = this.search?.value || "";
          this._destroyPopover();
          this.setup();
          if (this.search) this.search.value = prevSearch;
        }
        this._fp.open();
        this._onOpen();
      }
    };
    this.trigger.addEventListener("click", this._onTriggerClick);

    // Option clicks via data-event / data-params
    if (this.list) {
      this._onListClick = (e) => {
        const btn = e.target.closest("[data-event]");
        if (!btn) return;

        const event = btn.dataset.event;
        let payload = {};
        try {
          payload = JSON.parse(btn.dataset.params);
        } catch {
          /* empty */
        }

        this._push(event, payload);

        if (this.mode === "select") {
          requestAnimationFrame(() => this._fp.close());
        }
      };
      this.list.addEventListener("click", this._onListClick);
    }

    // Search filtering
    if (this.search) {
      this._onSearchInput = () => this.filter();
      this.search.addEventListener("input", this._onSearchInput);
    }

    // Add-input for multi_select: push on Enter
    if (this.addInput) {
      this._onAddKeydown = (e) => {
        if (e.key !== "Enter") return;
        e.preventDefault();
        const value = this.addInput.value.trim();
        if (!value) return;

        this._push("multi_select_keydown", {
          id: this.addInput.dataset.blockId,
          key: "Enter",
          value,
        });

        requestAnimationFrame(() => {
          this.addInput.value = "";
        });
      };
      this.addInput.addEventListener("keydown", this._onAddKeydown);
    }
  },

  _onOpen() {
    // Measure trigger width on demand (deferred from setup to avoid forced reflow)
    if (this._needsWidthMeasure && this._fp) {
      const width = Math.round(this.trigger.getBoundingClientRect().width);
      this._fp.el.style.width = `${Math.max(width, 224)}px`;
      this._needsWidthMeasure = false;
    }

    if (this.search) {
      this.search.value = "";
      this.filter();
      requestAnimationFrame(() => this.search.focus());
    }
  },

  _push(event, payload) {
    if (this.target) {
      this.pushEventTo(this.target, event, payload);
    } else {
      this.pushEvent(event, payload);
    }
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

    if (this.empty) {
      this.empty.style.display = visible === 0 ? "" : "none";
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

  _destroyPopover() {
    if (this.trigger && this._onTriggerClick) {
      this.trigger.removeEventListener("click", this._onTriggerClick);
    }
    if (this.list && this._onListClick) {
      this.list.removeEventListener("click", this._onListClick);
    }
    if (this.search && this._onSearchInput) {
      this.search.removeEventListener("input", this._onSearchInput);
    }
    if (this.addInput && this._onAddKeydown) {
      this.addInput.removeEventListener("keydown", this._onAddKeydown);
    }
    this._fp?.destroy();
    this._fp = null;
  },

  destroyed() {
    this._destroyPopover();
  },
};

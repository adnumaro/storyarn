/**
 * TableCellSelect — LiveView hook for select & multi-select table cells.
 *
 * Handles both modes via `data-mode="select"|"multi_select"`:
 *   - select: click option -> push event -> close popover
 *   - multi_select: click option -> push event -> popover stays open
 *
 * Uses shared floating_popover utility (@floating-ui/dom + body append)
 * so the dropdown escapes overflow:hidden/clip table containers.
 *
 * Expected DOM structure (server-rendered):
 *   <div phx-hook="TableCellSelect" id="..." data-mode="select|multi_select">
 *     <button data-role="trigger">...</button>
 *     <template data-role="popover-template">
 *       <input data-role="search" />
 *       <div data-role="list">
 *         <button data-search-text="..." phx-click="...">label</button>
 *       </div>
 *       <input data-role="add-input" phx-keydown="..." />
 *       <div data-role="empty">No matches</div>
 *     </template>
 *   </div>
 */
import { createFloatingPopover } from "../utils/floating_popover";

export const TableCellSelect = {
  mounted() {
    this.setup();
  },

  updated() {
    // Options/badges may have changed — rebuild popover content
    const wasOpen = this._fp?.isOpen;
    const prevSearch = this.search?.value || "";
    this._destroyPopover();
    this.setup();
    if (wasOpen) {
      this._fp.open();
      this._onOpen();
      this.search.value = prevSearch;
      this.filter();
    }
  },

  setup() {
    this.trigger = this.el.querySelector('[data-role="trigger"]');
    this.template = this.el.querySelector('[data-role="popover-template"]');
    this.mode = this.el.dataset.mode || "select";

    if (!this.trigger || !this.template) return;

    // Create floating popover (appended to body)
    this._fp = createFloatingPopover(this.trigger, {
      class: "bg-base-200 border border-base-content/20 rounded-lg shadow-lg",
      width: "14rem",
    });

    // Move template content into the floating container
    const content = this.template.content.cloneNode(true);
    this._fp.el.appendChild(content);

    // Query inside the floating container
    this.search = this._fp.el.querySelector('[data-role="search"]');
    this.list = this._fp.el.querySelector('[data-role="list"]');
    this.empty = this._fp.el.querySelector('[data-role="empty"]');
    this.addInput = this._fp.el.querySelector('[data-role="add-input"]');

    // Trigger click toggles
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

    // Option clicks: select mode closes, multi_select stays open
    if (this.list) {
      this._onListClick = (e) => {
        const btn = e.target.closest("[phx-click]");
        if (!btn) return;

        // Re-push the event from the hook so LiveView receives it
        // (elements cloned into body are outside the LiveView DOM tree)
        const event = btn.getAttribute("phx-click");
        const payload = {};
        for (const attr of btn.attributes) {
          if (attr.name.startsWith("phx-value-")) {
            payload[attr.name.replace("phx-value-", "")] = attr.value;
          }
        }

        const target =
          btn.closest("[phx-target]")?.getAttribute("phx-target") ||
          this.el.querySelector("[phx-target]")?.getAttribute("phx-target");

        if (target) {
          this.pushEventTo(target, event, payload);
        } else {
          this.pushEvent(event, payload);
        }

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

    // Add-input: push event from hook, clear input on Enter
    if (this.addInput) {
      this._onAddKeydown = (e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          const event = this.addInput.getAttribute("phx-keydown");
          if (!event) return;

          const payload = { key: "Enter" };
          for (const attr of this.addInput.attributes) {
            if (attr.name.startsWith("phx-value-")) {
              payload[attr.name.replace("phx-value-", "")] = attr.value;
            }
          }
          payload.value = this.addInput.value;

          const target =
            this.addInput.getAttribute("phx-target") ||
            this.el.querySelector("[phx-target]")?.getAttribute("phx-target");

          if (target) {
            this.pushEventTo(target, event, payload);
          } else {
            this.pushEvent(event, payload);
          }

          requestAnimationFrame(() => {
            this.addInput.value = "";
          });
        }
      };
      this.addInput.addEventListener("keydown", this._onAddKeydown);
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

  destroyed() {
    this._destroyPopover();
  },
};

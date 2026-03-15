import { FileText, Zap } from "lucide";
import { createIconHTML } from "../flow_canvas/node_config.js";
import { createFloatingPopover } from "../utils/floating_popover";

const SHEET_ICON = createIconHTML(FileText, { size: 16 });
const FLOW_ICON = createIconHTML(Zap, { size: 16 });

export const ReferenceSelect = {
  mounted() {
    this.results = [];
    this._hasSearched = false;
    this.setup();

    this.handleEvent("reference_results", ({ block_id, results }) => {
      if (block_id.toString() !== this.blockId) return;

      this.results = results;
      this._hasSearched = true;
      this.renderResults(results);
    });
  },

  updated() {
    const wasOpen = this._fp?.isOpen ?? false;
    const prevSearch = this.search?.value || "";
    const prevResults = this.results;
    const prevHasSearched = this._hasSearched;

    this._destroyPopover();
    this.setup();

    this.results = prevResults;
    this._hasSearched = prevHasSearched;

    if (wasOpen && this._fp) {
      this._fp.open();

      if (this.search) {
        this.search.value = prevSearch;
      }

      if (prevHasSearched) {
        this.renderResults(prevResults);
      } else {
        this.renderIdleState();
      }

      requestAnimationFrame(() => this.search?.focus());
    }
  },

  setup() {
    this.blockId = this.el.dataset.blockId;
    this.target = this.el.dataset.phxTarget || null;
    this.idleText = this.el.dataset.idleText || "Type to search...";
    this.noResultsText = this.el.dataset.noResultsText || "No results found";

    this.trigger = this.el.querySelector('[data-role="trigger"]');
    this.template = this.el.querySelector('[data-role="popover-template"]');

    if (!this.trigger || !this.template) return;

    this._fp = createFloatingPopover(this.trigger, {
      class: "bg-base-100 border border-base-300 rounded-lg shadow-lg",
      width: this._popoverWidth(),
    });

    const content = this.template.content.cloneNode(true);
    this._fp.el.appendChild(content);

    this.search = this._fp.el.querySelector('[data-role="search"]');
    this.list = this._fp.el.querySelector('[data-role="list"]');
    this.clearButton = this._fp.el.querySelector('[data-role="clear"]');

    this._onTriggerClick = (e) => {
      e.preventDefault();
      e.stopPropagation();

      if (this._fp.isOpen) {
        this._fp.close();
      } else {
        this._fp.open();
        this._onOpen();
      }
    };

    this.trigger.addEventListener("click", this._onTriggerClick);

    if (this.search) {
      this._onSearchInput = () => {
        const query = this.search.value || "";

        clearTimeout(this._searchTimer);
        this._searchTimer = setTimeout(() => {
          this._hasSearched = true;
          this._push("search_references", {
            "block-id": this.blockId,
            value: query,
          });
        }, 300);
      };

      this.search.addEventListener("input", this._onSearchInput);
    }

    if (this.list) {
      this._onListClick = (e) => {
        const button = e.target.closest("[data-reference-id]");
        if (!button) return;

        this._fp.close();
        this._push("select_reference", {
          "block-id": this.blockId,
          type: button.dataset.referenceType,
          id: button.dataset.referenceId,
        });
      };

      this.list.addEventListener("click", this._onListClick);
    }

    if (this.clearButton) {
      this._onClearClick = (e) => {
        e.preventDefault();
        this._fp.close();
        this._push("clear_reference", { "block-id": this.blockId });
      };

      this.clearButton.addEventListener("click", this._onClearClick);
    }
  },

  _onOpen() {
    this._hasSearched = false;
    this.results = [];
    this.renderIdleState();

    if (this.search) {
      this.search.value = "";
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

  _popoverWidth() {
    const width = Math.round(this.trigger.getBoundingClientRect().width);
    return `${Math.max(width, 224)}px`;
  },

  _destroyPopover() {
    clearTimeout(this._searchTimer);
    this._searchTimer = null;

    if (this.trigger && this._onTriggerClick) {
      this.trigger.removeEventListener("click", this._onTriggerClick);
    }

    if (this.search && this._onSearchInput) {
      this.search.removeEventListener("input", this._onSearchInput);
    }

    if (this.list && this._onListClick) {
      this.list.removeEventListener("click", this._onListClick);
    }

    if (this.clearButton && this._onClearClick) {
      this.clearButton.removeEventListener("click", this._onClearClick);
    }

    this._fp?.destroy();
    this._fp = null;
    this.search = null;
    this.list = null;
    this.clearButton = null;
  },

  renderIdleState() {
    this.renderMessage(this.idleText);
  },

  renderResults(results) {
    if (!this.list) return;

    if (results.length === 0) {
      this.renderMessage(this.noResultsText);
      return;
    }

    const html = results
      .map(
        (result) => `
          <button
            type="button"
            class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
            data-reference-id="${result.id}"
            data-reference-type="${result.type}"
          >
            <span class="flex-shrink-0 size-6 rounded flex items-center justify-center text-xs ${
              result.type === "sheet"
                ? "bg-primary/20 text-primary"
                : "bg-secondary/20 text-secondary"
            }">
              ${result.type === "sheet" ? SHEET_ICON : FLOW_ICON}
            </span>
            <span class="truncate">${this.escapeHtml(result.name)}</span>
            ${
              result.shortcut
                ? `<span class="text-base-content/50 text-sm ml-auto">#${this.escapeHtml(result.shortcut)}</span>`
                : ""
            }
          </button>
        `,
      )
      .join("");

    this.list.innerHTML = html;
  },

  renderMessage(text) {
    if (!this.list) return;

    this.list.innerHTML = `
      <div class="text-center text-base-content/50 py-4 text-sm">
        ${this.escapeHtml(text)}
      </div>
    `;
  },

  escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  },

  destroyed() {
    this._destroyPopover();
  },
};

import { FileText, Zap } from "lucide";
import { createIconHTML } from "../flow_canvas/node_config.js";

// Pre-create icon HTML strings
const SHEET_ICON = createIconHTML(FileText, { size: 16 });
const FLOW_ICON = createIconHTML(Zap, { size: 16 });

/**
 * ReferenceSearch hook for handling reference block search results.
 * Receives search results from the server and displays them.
 */
export const ReferenceSearch = {
  mounted() {
    this.blockId = this.el.dataset.blockId;

    // Listen for search results from server
    this.handleEvent("reference_results", ({ block_id, results }) => {
      if (block_id.toString() !== this.blockId) return;

      this.renderResults(results);
    });
  },

  renderResults(results) {
    if (results.length === 0) {
      this.el.innerHTML = `
        <div class="text-center text-base-content/50 py-4 text-sm">
          No results found
        </div>
      `;
      return;
    }

    const html = results
      .map(
        (result) => `
        <button
          type="button"
          class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
          phx-click="select_reference"
          phx-value-block-id="${this.blockId}"
          phx-value-type="${result.type}"
          phx-value-id="${result.id}"
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

    this.el.innerHTML = html;
  },

  escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  },
};

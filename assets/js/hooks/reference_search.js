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
            result.type === "sheet" ? "bg-primary/20 text-primary" : "bg-secondary/20 text-secondary"
          }">
            <svg class="size-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              ${
                result.type === "sheet"
                  ? '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>'
                  : '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>'
              }
            </svg>
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

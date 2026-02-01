/**
 * TreeSearch hook for client-side tree filtering.
 *
 * Usage:
 * <div id="pages-tree-search" phx-hook="TreeSearch" data-tree-id="pages-tree-container">
 *   <input type="text" data-tree-search-input placeholder="Filter pages..." />
 * </div>
 *
 * The tree items should have data-page-name and data-page-id attributes.
 * Parent containers should have data-parent-id attributes.
 */
export const TreeSearch = {
  mounted() {
    this.input = this.el.querySelector("[data-tree-search-input]");
    this.treeId = this.el.dataset.treeId;
    this.savedExpandState = new Map();
    this.isFiltering = false;

    if (this.input) {
      this.input.addEventListener("input", this.handleInput.bind(this));
      this.input.addEventListener("keydown", this.handleKeydown.bind(this));
    }
  },

  handleKeydown(event) {
    // Clear search on Escape
    if (event.key === "Escape") {
      this.input.value = "";
      this.clearFilter();
    }
  },

  handleInput(event) {
    const query = event.target.value.toLowerCase().trim();

    if (query === "") {
      this.clearFilter();
    } else {
      this.filterTree(query);
    }
  },

  filterTree(query) {
    const tree = document.getElementById(this.treeId);
    if (!tree) return;

    // Save expand state before filtering (only once)
    if (!this.isFiltering) {
      this.saveExpandState(tree);
      this.isFiltering = true;
    }

    const allNodes = tree.querySelectorAll("[data-page-id]");
    const matchingIds = new Set();
    const ancestorIds = new Set();

    // Find matching nodes and their ancestors
    for (const node of allNodes) {
      const pageName = (node.dataset.pageName || "").toLowerCase();
      if (pageName.includes(query)) {
        matchingIds.add(node.dataset.pageId);
        // Walk up to find all ancestors
        this.collectAncestors(node, ancestorIds);
      }
    }

    // Show/hide nodes based on match or ancestor status
    for (const node of allNodes) {
      const pageId = node.dataset.pageId;
      const isMatch = matchingIds.has(pageId);
      const isAncestor = ancestorIds.has(pageId);
      const shouldShow = isMatch || isAncestor;

      node.style.display = shouldShow ? "" : "none";

      // Highlight matching nodes
      if (isMatch) {
        node.classList.add("bg-primary/10");
      } else {
        node.classList.remove("bg-primary/10");
      }

      // Auto-expand ancestors
      if (isAncestor || isMatch) {
        this.expandNode(node);
      }
    }
  },

  collectAncestors(node, ancestorIds) {
    let current = node.parentElement;
    while (current) {
      // Check if we're inside a tree node's children container
      const parentNode = current.closest("[data-page-id]");
      if (parentNode && parentNode !== node) {
        ancestorIds.add(parentNode.dataset.pageId);
        current = parentNode.parentElement;
      } else {
        break;
      }
    }
  },

  expandNode(node) {
    // Find the expand/collapse content for this node
    const nodeId = node.dataset.pageId;
    const content = document.getElementById(`tree-content-page-${nodeId}`);
    const chevron = document.querySelector(`#tree-toggle-page-${nodeId} [data-chevron]`);

    if (content) {
      content.classList.remove("hidden");
    }
    if (chevron) {
      chevron.classList.add("rotate-90");
    }
  },

  saveExpandState(tree) {
    this.savedExpandState.clear();
    const contents = tree.querySelectorAll("[id^='tree-content-']");
    for (const content of contents) {
      const nodeId = content.id.replace("tree-content-page-", "");
      this.savedExpandState.set(nodeId, !content.classList.contains("hidden"));
    }
  },

  clearFilter() {
    const tree = document.getElementById(this.treeId);
    if (!tree) return;

    const allNodes = tree.querySelectorAll("[data-page-id]");

    // Show all nodes and remove highlights
    for (const node of allNodes) {
      node.style.display = "";
      node.classList.remove("bg-primary/10");
    }

    // Restore previous expand state
    if (this.isFiltering) {
      for (const [nodeId, wasExpanded] of this.savedExpandState) {
        const content = document.getElementById(`tree-content-page-${nodeId}`);
        const chevron = document.querySelector(`#tree-toggle-page-${nodeId} [data-chevron]`);

        if (content) {
          content.classList.toggle("hidden", !wasExpanded);
        }
        if (chevron) {
          chevron.classList.toggle("rotate-90", wasExpanded);
        }
      }
      this.isFiltering = false;
    }
  },

  destroyed() {
    this.savedExpandState.clear();
  },
};

export default { TreeSearch };

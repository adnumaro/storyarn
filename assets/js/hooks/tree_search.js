/**
 * TreeSearch hook for client-side tree filtering.
 *
 * Usage:
 * <div id="sheets-tree-search" phx-hook="TreeSearch" data-tree-id="sheets-tree-container">
 *   <input type="text" data-tree-search-input placeholder="Filter sheets..." />
 * </div>
 *
 * The tree items should have data-item-name and data-item-id attributes.
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

    const allNodes = tree.querySelectorAll("[data-item-id]");
    const matchingIds = new Set();
    const ancestorIds = new Set();

    // Find matching nodes and their ancestors
    for (const node of allNodes) {
      const itemName = (node.dataset.itemName || "").toLowerCase();
      if (itemName.includes(query)) {
        matchingIds.add(node.dataset.itemId);
        // Walk up to find all ancestors
        this.collectAncestors(node, ancestorIds);
      }
    }

    // Show/hide nodes based on match or ancestor status
    for (const node of allNodes) {
      const nodeId = node.dataset.itemId;
      const isMatch = matchingIds.has(nodeId);
      const isAncestor = ancestorIds.has(nodeId);
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
      const parentNode = current.closest("[data-item-id]");
      if (parentNode && parentNode !== node) {
        ancestorIds.add(parentNode.dataset.itemId);
        current = parentNode.parentElement;
      } else {
        break;
      }
    }
  },

  expandNode(node) {
    // Find the content container and chevron within this node using DOM traversal
    const content = node.querySelector(":scope > [id^='tree-content-']");
    const chevron = node.querySelector(":scope [data-chevron]");

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
      this.savedExpandState.set(content.id, !content.classList.contains("hidden"));
    }
  },

  clearFilter() {
    const tree = document.getElementById(this.treeId);
    if (!tree) return;

    const allNodes = tree.querySelectorAll("[data-item-id]");

    // Show all nodes and remove highlights
    for (const node of allNodes) {
      node.style.display = "";
      node.classList.remove("bg-primary/10");
    }

    // Restore previous expand state
    if (this.isFiltering) {
      for (const [contentId, wasExpanded] of this.savedExpandState) {
        const content = document.getElementById(contentId);
        // Find the chevron in the same parent node
        const parentNode = content?.parentElement;
        const chevron = parentNode?.querySelector(":scope [data-chevron]");

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

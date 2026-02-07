/**
 * LiveView hook for the Instruction Builder.
 *
 * Manages the assignments array client-side and pushes the full state
 * back to LiveView on every meaningful change.
 *
 * Communication:
 * - Receives initial data from data-* attributes (read in mounted())
 * - Pushes: "update_instruction_builder" event with { assignments: [...] }
 * - Listens: "node_updated" push event for collaboration updates
 *
 * The element uses phx-update="ignore" so LiveView won't clear
 * JS-rendered children on re-render.
 */

import { createAssignmentRow } from "./assignment_row";

export const InstructionBuilder = {
  mounted() {
    this.nodeId = null;
    this.assignments = JSON.parse(this.el.dataset.assignments || "[]");
    this.variables = JSON.parse(this.el.dataset.variables || "[]");
    this.canEdit = JSON.parse(this.el.dataset.canEdit || "true");
    this._pendingPushCount = 0;

    // Extract node ID from element ID (format: "instruction-builder-{nodeId}")
    const idMatch = this.el.id.match(/instruction-builder-(\d+)/);
    if (idMatch) this.nodeId = parseInt(idMatch[1], 10);

    this.pagesWithVariables = groupVariablesByPage(this.variables);
    this.rows = [];
    this.render();

    // Listen for server push events (collaboration updates)
    this.handleEvent("node_updated", (data) => {
      // Only handle updates for our node
      if (data.id !== this.nodeId) return;

      // Skip if this is our own update coming back
      if (this._pendingPushCount > 0) {
        this._pendingPushCount--;
        return;
      }

      // External update — refresh from server data
      const newAssignments = data.data?.assignments || [];
      if (!deepEqual(newAssignments, this.assignments)) {
        this.assignments = newAssignments;
        this.render();
      }
    });
  },

  // Note: no updated() callback — phx-update="ignore" prevents LiveView
  // from touching this element. Collaboration updates arrive via handleEvent.

  destroyed() {
    this.destroyRows();
  },

  destroyRows() {
    if (this.rows) {
      this.rows.forEach((row) => row.destroy?.());
      this.rows = [];
    }
  },

  pushAssignments() {
    this._pendingPushCount++;
    this.pushEvent("update_instruction_builder", {
      assignments: this.assignments,
    });
  },

  render() {
    this.destroyRows();
    this.el.innerHTML = "";

    const rowsContainer = document.createElement("div");
    rowsContainer.className = "space-y-0";
    this.el.appendChild(rowsContainer);

    this.assignments.forEach((assignment, index) => {
      const rowEl = document.createElement("div");
      rowsContainer.appendChild(rowEl);

      const row = createAssignmentRow({
        container: rowEl,
        assignment,
        variables: this.variables,
        pagesWithVariables: this.pagesWithVariables,
        canEdit: this.canEdit,
        onChange: (updatedAssignment) => {
          this.assignments[index] = updatedAssignment;
          this.pushAssignments();
        },
        onRemove: () => {
          this.assignments.splice(index, 1);
          this.pushAssignments();
          this.render();
        },
        onAdvance: () => {
          const nextRow = this.rows[index + 1];
          if (nextRow) {
            nextRow.focusFirstEmpty();
          } else if (this.addButton) {
            this.addButton.focus();
          }
        },
      });

      this.rows.push(row);
    });

    // Add assignment button
    if (this.canEdit) {
      const addBtn = document.createElement("button");
      addBtn.type = "button";
      addBtn.className =
        "btn btn-ghost btn-xs gap-1 border border-dashed border-base-300 mt-2";
      addBtn.innerHTML =
        '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg> Add assignment';
      addBtn.addEventListener("click", () => {
        const newAssignment = {
          id: `assign_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
          page: null,
          variable: null,
          operator: "set",
          value: null,
          value_type: "literal",
          value_page: null,
        };
        this.assignments.push(newAssignment);
        this.pushAssignments();
        this.render();

        requestAnimationFrame(() => {
          const lastRow = this.rows[this.rows.length - 1];
          if (lastRow) lastRow.focusFirstEmpty();
        });
      });

      this.addButton = addBtn;
      this.el.appendChild(addBtn);
    }

    // Empty state
    if (this.assignments.length === 0 && !this.canEdit) {
      const empty = document.createElement("p");
      empty.className = "text-xs text-base-content/50 italic";
      empty.textContent = "No assignments";
      this.el.appendChild(empty);
    }
  },
};

/**
 * Groups flat variable list into pages with their variables.
 */
function groupVariablesByPage(variables) {
  const pageMap = new Map();

  for (const v of variables) {
    const key = v.page_shortcut;
    if (!pageMap.has(key)) {
      pageMap.set(key, {
        shortcut: v.page_shortcut,
        name: v.page_name || v.page_shortcut,
        vars: [],
      });
    }
    pageMap.get(key).vars.push({
      variable_name: v.variable_name,
      block_type: v.block_type,
      options: v.options,
    });
  }

  return Array.from(pageMap.values()).sort((a, b) =>
    a.name.localeCompare(b.name),
  );
}

/**
 * Deep equality comparison for assignments arrays.
 * Handles different key ordering between JS and Elixir JSON.
 */
function deepEqual(a, b) {
  if (a === b) return true;
  if (a == null || b == null) return a == b;
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return false;
    return a.every((item, i) => deepEqual(item, b[i]));
  }
  if (typeof a === "object" && typeof b === "object") {
    const keysA = Object.keys(a).sort();
    const keysB = Object.keys(b).sort();
    if (keysA.length !== keysB.length) return false;
    return keysA.every(
      (key, i) => keysB[i] === key && deepEqual(a[key], b[key]),
    );
  }
  return false;
}

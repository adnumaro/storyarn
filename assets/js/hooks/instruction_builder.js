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

import { createElement, Plus } from "lucide";
import { createAssignmentRow } from "../instruction_builder/assignment_row";

const DEFAULT_TRANSLATIONS = {
  add_assignment: "Add assignment",
  no_assignments: "No assignments",
  placeholder_sheet: "sheet",
  placeholder_variable: "variable",
  placeholder_value: "value",
};

export const InstructionBuilder = {
  mounted() {
    this.nodeId = null;
    this.assignments = JSON.parse(this.el.dataset.assignments || "[]");
    this.variables = JSON.parse(this.el.dataset.variables || "[]");
    this.canEdit = JSON.parse(this.el.dataset.canEdit || "true");
    this.context = JSON.parse(this.el.dataset.context || "{}");
    this.eventName = this.el.dataset.eventName || null;
    this.t = {
      ...DEFAULT_TRANSLATIONS,
      ...JSON.parse(this.el.dataset.translations || "{}"),
    };
    this._pendingPushCount = 0;

    // Extract node ID from element ID (format: "instruction-builder-{nodeId}")
    const idMatch = this.el.id.match(/instruction-builder-(\d+)/);
    if (idMatch) this.nodeId = parseInt(idMatch[1], 10);

    this.sheetsWithVariables = groupVariablesBySheet(this.variables);
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

    // Custom event name — used by screenplay editor and other consumers
    if (this.eventName) {
      this.pushEvent(this.eventName, {
        assignments: this.assignments,
        ...this.context,
      });
      return;
    }

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
        sheetsWithVariables: this.sheetsWithVariables,
        canEdit: this.canEdit,
        translations: this.t,
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
      addBtn.appendChild(createElement(Plus, { width: 12, height: 12 }));
      addBtn.append(` ${this.t.add_assignment}`);
      addBtn.addEventListener("click", () => {
        const newAssignment = {
          id: `assign_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
          sheet: null,
          variable: null,
          operator: "set",
          value: null,
          value_type: "literal",
          value_sheet: null,
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
      empty.textContent = this.t.no_assignments;
      this.el.appendChild(empty);
    }
  },
};

/**
 * Groups flat variable list into sheets with their variables.
 */
function groupVariablesBySheet(variables) {
  const sheetMap = new Map();

  for (const v of variables) {
    const key = v.sheet_shortcut;
    if (!sheetMap.has(key)) {
      sheetMap.set(key, {
        shortcut: v.sheet_shortcut,
        name: v.sheet_name || v.sheet_shortcut,
        vars: [],
      });
    }
    sheetMap.get(key).vars.push({
      variable_name: v.variable_name,
      block_type: v.block_type,
      options: v.options,
    });
  }

  return Array.from(sheetMap.values()).sort((a, b) =>
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

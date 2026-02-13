/**
 * Instruction builder core — reusable rendering logic for instruction/assignment UI.
 *
 * Used by both the InstructionBuilder LiveView hook (flow editor) and the
 * Instruction TipTap NodeView (screenplay editor). Accepts a pushEvent
 * callback instead of relying on a LiveView hook directly.
 */

import { createElement, Plus } from "lucide";
import { createAssignmentRow } from "../../instruction_builder/assignment_row";
import { groupVariablesBySheet } from "./utils.js";

const DEFAULT_TRANSLATIONS = {
  add_assignment: "Add assignment",
  no_assignments: "No assignments",
  placeholder_sheet: "sheet",
  placeholder_variable: "variable",
  placeholder_value: "value",
};

/**
 * Create an instruction builder UI inside the given container.
 *
 * @param {Object} opts
 * @param {HTMLElement} opts.container - DOM element to render into
 * @param {Array} opts.assignments - Initial assignments array
 * @param {Array} opts.variables - Flat variable list
 * @param {boolean} opts.canEdit - Whether editing is allowed
 * @param {Object} opts.context - Context map for event payload
 * @param {string} opts.eventName - Event name to push
 * @param {Function} opts.pushEvent - Callback: pushEvent(eventName, payload)
 * @param {Object} [opts.translations] - Optional translation overrides
 * @returns {{ destroy: Function, update: Function }}
 */
export function createInstructionBuilder({
  container,
  assignments,
  variables,
  canEdit,
  context,
  eventName,
  pushEvent,
  translations,
}) {
  let currentAssignments = assignments || [];
  const sheetsWithVariables = groupVariablesBySheet(variables || []);
  let rows = [];
  let addButton = null;

  const t = { ...DEFAULT_TRANSLATIONS, ...translations };

  function push() {
    pushEvent(eventName, {
      assignments: currentAssignments,
      ...context,
    });
  }

  function destroyRows() {
    rows.forEach((row) => row.destroy?.());
    rows = [];
  }

  function render() {
    destroyRows();
    container.innerHTML = "";

    const rowsContainer = document.createElement("div");
    rowsContainer.className = "space-y-0";
    container.appendChild(rowsContainer);

    currentAssignments.forEach((assignment, index) => {
      const rowEl = document.createElement("div");
      rowsContainer.appendChild(rowEl);

      const row = createAssignmentRow({
        container: rowEl,
        assignment,
        variables: variables || [],
        sheetsWithVariables,
        canEdit,
        translations: t,
        onChange: (updatedAssignment) => {
          currentAssignments[index] = updatedAssignment;
          push();
        },
        onRemove: () => {
          currentAssignments.splice(index, 1);
          push();
          render();
        },
        onAdvance: () => {
          const nextRow = rows[index + 1];
          if (nextRow) {
            nextRow.focusFirstEmpty();
          } else if (addButton) {
            addButton.focus();
          }
        },
      });

      rows.push(row);
    });

    // Add assignment button
    if (canEdit) {
      const addBtn = document.createElement("button");
      addBtn.type = "button";
      addBtn.className =
        "btn btn-ghost btn-xs gap-1 border border-dashed border-base-300 mt-2";
      addBtn.appendChild(createElement(Plus, { width: 12, height: 12 }));
      addBtn.append(` ${t.add_assignment}`);
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
        currentAssignments.push(newAssignment);
        push();
        render();

        requestAnimationFrame(() => {
          const lastRow = rows[rows.length - 1];
          if (lastRow) lastRow.focusFirstEmpty();
        });
      });

      addButton = addBtn;
      container.appendChild(addBtn);
    }

    // Empty state
    if (currentAssignments.length === 0 && !canEdit) {
      const empty = document.createElement("p");
      empty.className = "text-xs text-base-content/50 italic";
      empty.textContent = t.no_assignments;
      container.appendChild(empty);
    }
  }

  // Initial render
  render();

  return {
    destroy() {
      destroyRows();
      container.innerHTML = "";
    },
    update(newAssignments) {
      currentAssignments = newAssignments || [];
      render();
    },
  };
}

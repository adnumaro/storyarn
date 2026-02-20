/**
 * LiveView hook for the Instruction Builder.
 *
 * Thin wrapper around instruction_builder_core.js — delegates all rendering
 * logic to the core module while providing the LiveView hook interface.
 *
 * Communication:
 * - Receives initial data from data-* attributes (read in mounted())
 * - Pushes: "update_instruction_builder" event with { assignments: [...] }
 * - Listens: "node_updated" push event for collaboration updates
 *
 * The element uses phx-update="ignore" so LiveView won't clear
 * JS-rendered children on re-render.
 */

import { createInstructionBuilder } from "../screenplay/builders/instruction_builder_core.js";
import { deepEqual } from "../utils/deep_equal.js";

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
    this._pendingPushCount = 0;

    this.t = {
      ...DEFAULT_TRANSLATIONS,
      ...JSON.parse(this.el.dataset.translations || "{}"),
    };

    // Extract node ID from element ID (format: "instruction-builder-{nodeId}")
    const idMatch = this.el.id.match(/instruction-builder-(\d+)/);
    if (idMatch) this.nodeId = parseInt(idMatch[1], 10);

    // Resolve the event name
    const resolvedEventName = this.eventName || "update_instruction_builder";

    const pushEvent = (name, payload) => {
      this._pendingPushCount++;

      if (this.eventName) {
        this.pushEvent(name, payload);
      } else {
        this.pushEvent(resolvedEventName, {
          assignments: payload.assignments,
        });
      }
    };

    this.builderInstance = createInstructionBuilder({
      container: this.el,
      assignments: this.assignments,
      variables: this.variables,
      canEdit: this.canEdit,
      context: this.context,
      eventName: resolvedEventName,
      pushEvent,
      translations: this.t,
    });

    // Listen for server push events (collaboration updates)
    this.handleEvent("node_updated", (data) => {
      if (data.id !== this.nodeId) return;

      if (this._pendingPushCount > 0) {
        this._pendingPushCount--;
        return;
      }

      const newAssignments = data.data?.assignments || [];
      if (!deepEqual(newAssignments, this.assignments)) {
        this.assignments = newAssignments;
        this.builderInstance.update(newAssignments);
      }
    });
  },

  destroyed() {
    if (this.builderInstance) {
      this.builderInstance.destroy();
      this.builderInstance = null;
    }
  },
};

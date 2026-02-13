/**
 * LiveView hook for the Condition Builder.
 *
 * Thin wrapper around condition_builder_core.js — delegates all rendering
 * logic to the core module while providing the LiveView hook interface
 * (mounted, destroyed, handleEvent).
 *
 * Communication:
 * - Receives initial data from data-* attributes (read in mounted())
 * - Pushes: "update_condition_builder" or custom event via eventName
 * - Listens: "node_updated" push event for collaboration updates
 *
 * The element uses phx-update="ignore" so LiveView won't clear
 * JS-rendered children on re-render.
 */

import { createConditionBuilder } from "../screenplay/builders/condition_builder_core.js";
import { OPERATOR_LABELS as DEFAULT_OPERATOR_LABELS } from "../condition_builder/condition_sentence_templates";
import { deepEqual } from "../utils/deep_equal.js";

export const ConditionBuilder = {
  mounted() {
    this.nodeId = null;
    this.condition = JSON.parse(this.el.dataset.condition || '{"logic":"all","rules":[]}');
    this.variables = JSON.parse(this.el.dataset.variables || "[]");
    this.canEdit = JSON.parse(this.el.dataset.canEdit || "true");
    this.switchMode = JSON.parse(this.el.dataset.switchMode || "false");
    this.context = JSON.parse(this.el.dataset.context || "{}");
    this.eventName = this.el.dataset.eventName || null;
    this._pendingPushCount = 0;

    const userTranslations = JSON.parse(this.el.dataset.translations || "{}");
    this.t = {
      operator_labels: {
        ...DEFAULT_OPERATOR_LABELS,
        ...(userTranslations.operator_labels || {}),
      },
      ...userTranslations,
    };

    // Extract node ID from element ID (format: "condition-builder-{nodeId}")
    const idMatch = this.el.id.match(/condition-builder-(\d+)/);
    if (idMatch) this.nodeId = parseInt(idMatch[1], 10);

    // For response conditions, extract from context
    if (!this.nodeId && this.context["node-id"]) {
      this.nodeId = parseInt(this.context["node-id"], 10);
    }

    // Resolve the event name — custom or default based on context
    const resolvedEventName =
      this.eventName ||
      (this.context["response-id"]
        ? "update_response_condition_builder"
        : "update_condition_builder");

    // Build the push callback that wraps this.pushEvent
    const hook = this;
    const pushEvent = (name, payload) => {
      hook._pendingPushCount++;

      if (hook.eventName) {
        // Custom event name (screenplay editor): pass event name + context directly
        hook.pushEvent(name, payload);
      } else if (hook.context["response-id"]) {
        // Response condition: include response context
        hook.pushEvent(resolvedEventName, {
          condition: payload.condition,
          "response-id": hook.context["response-id"],
          "node-id": hook.context["node-id"],
        });
      } else {
        // Default: just push condition
        hook.pushEvent(resolvedEventName, { condition: payload.condition });
      }
    };

    this.builderInstance = createConditionBuilder({
      container: this.el,
      condition: this.condition,
      variables: this.variables,
      canEdit: this.canEdit,
      switchMode: this.switchMode,
      context: this.context,
      eventName: resolvedEventName,
      pushEvent,
      translations: this.t,
    });

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
      let newCondition;
      if (this.context["response-id"]) {
        // For response conditions, find our response in the data
        const responses = data.data?.responses || [];
        const response = responses.find(
          (r) => r.id === this.context["response-id"],
        );
        if (response && response.condition) {
          try {
            newCondition = JSON.parse(response.condition);
          } catch {
            return;
          }
        } else {
          return;
        }
      } else {
        newCondition = data.data?.condition;
      }

      if (newCondition && !deepEqual(newCondition, this.condition)) {
        this.condition = newCondition;
        this.switchMode = data.data?.switch_mode || false;
        this.builderInstance.update(newCondition);
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


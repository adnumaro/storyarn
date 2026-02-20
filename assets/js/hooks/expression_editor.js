/**
 * Phoenix LiveView hook for the CodeMirror expression editor.
 *
 * Dataset attributes:
 *   data-mode       "assignments" | "expression"
 *   data-content    Initial text content
 *   data-editable   "true" | "false"
 *   data-event-name Server event to push on change (default: auto-detected)
 *   data-context    JSON string of extra context to include in event payload
 *   data-variables  JSON array of {sheet_shortcut, variable_name, block_type}
 *   data-placeholder Placeholder text
 */

import { parseAssignments, parseCondition } from "../expression_editor/parser.js";
import { createExpressionEditor } from "../expression_editor/setup.js";

export const ExpressionEditor = {
  mounted() {
    this.mode = this.el.dataset.mode || "expression";
    this.content = this.el.dataset.content || "";
    this.editable = this.el.dataset.editable !== "false";
    this.context = JSON.parse(this.el.dataset.context || "{}");
    this.variables = JSON.parse(this.el.dataset.variables || "[]");

    // Determine event name: explicit > context-based default
    this.eventName = this.el.dataset.eventName || this._defaultEventName();

    this.editor = createExpressionEditor({
      container: this.el,
      content: this.content,
      mode: this.mode,
      editable: this.editable,
      placeholderText: this.el.dataset.placeholder || "",
      variables: this.variables,
      onChange: (text) => {
        this._pushParsedData(text);
      },
    });
  },

  destroyed() {
    this.editor?.destroy();
  },

  _defaultEventName() {
    if (this.mode === "expression") {
      return this.context["response-id"]
        ? "update_response_condition_builder"
        : "update_condition_builder";
    }
    return "update_instruction_builder";
  },

  _pushParsedData(text) {
    if (this.mode === "expression") {
      const result = parseCondition(text);
      if (result.errors.length > 0) return; // Don't push invalid data

      const condition = result.condition || { logic: "all", rules: [] };
      const payload = { condition };

      if (this.context["response-id"]) {
        payload["response-id"] = this.context["response-id"];
        payload["node-id"] = this.context["node-id"];
      }

      this.pushEvent(this.eventName, payload);
    } else {
      const result = parseAssignments(text);
      if (result.errors.length > 0) return;

      const assignments = result.assignments || [];
      this.pushEvent(this.eventName, { assignments });
    }
  },
};

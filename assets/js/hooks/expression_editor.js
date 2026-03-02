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

import { formatExpression } from "../expression_editor/formatter.js";
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
    this.translations = JSON.parse(this.el.dataset.translations || "{}");

    this.editor = createExpressionEditor({
      container: this.el,
      content: this.content,
      mode: this.mode,
      editable: this.editable,
      placeholderText: this.el.dataset.placeholder || "",
      variables: this.variables,
      translations: this.translations,
      onChange: (text) => {
        this._pushParsedData(text);
      },
    });

    this._isFormatting = false;
    this._formatResetTimer = null;
    this.el.addEventListener("expression-editor:format", () => this._format());

    // Auto-format on mount so the Code tab always shows formatted content.
    // _format() sets _isFormatting = true so the server data is not affected.
    if (this.content) this._format();
  },

  destroyed() {
    this.editor?.destroy();
    clearTimeout(this._formatResetTimer);
  },

  _defaultEventName() {
    if (this.mode === "expression") {
      return this.context["response-id"]
        ? "update_response_condition_builder"
        : "update_condition_builder";
    }
    return "update_instruction_builder";
  },

  _format() {
    const text = this.editor.getContent();
    const formatted = formatExpression(text, this.mode);
    if (formatted === text) return;

    // Suppress _pushParsedData for the duration of the format debounce.
    // Format is a display-only operation — it must not corrupt the server's
    // condition/assignment data by re-parsing the reformatted text (the parser
    // has known limitations with nested paren groups).
    this._isFormatting = true;
    clearTimeout(this._formatResetTimer);
    this.editor.setContent(formatted);
    // 350ms > 300ms debounce delay, so the flag is still set when the debounce fires.
    this._formatResetTimer = setTimeout(() => {
      this._isFormatting = false;
    }, 350);
  },

  _pushParsedData(text) {
    if (this._isFormatting) return;
    if (this.mode === "expression") {
      const result = parseCondition(text, this.variables);
      if (result.errors.length > 0) return; // Don't push invalid data

      const condition = result.condition || { logic: "all", rules: [] };
      const payload = { condition };

      if (this.context["response-id"]) {
        payload["response-id"] = this.context["response-id"];
        payload["node-id"] = this.context["node-id"];
      }

      this.pushEvent(this.eventName, payload);
    } else {
      const result = parseAssignments(text, this.variables);
      if (result.errors.length > 0) return;

      // Strip linter-only position metadata before sending to server
      const assignments = (result.assignments || []).map(
        // eslint-disable-next-line no-unused-vars
        ({ ref_from, ref_to, value_ref_from, value_ref_to, ...a }) => a,
      );
      this.pushEvent(this.eventName, { assignments, ...this.context });
    }
  },
};

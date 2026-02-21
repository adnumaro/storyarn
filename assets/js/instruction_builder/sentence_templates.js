/**
 * Sentence templates for instruction operators.
 *
 * Each template defines the order of elements in a row.
 * - "text" entries are static labels
 * - "slot" entries are interactive (combobox/input)
 *
 * When value_type == "variable_ref", the "value" slot is replaced by
 * "value_sheet" + separator + "value" (as variable combobox).
 */

export const SENTENCE_TEMPLATES = {
  set: [
    { type: "verb", value: "Set" },
    { type: "slot", key: "sheet", placeholder: "sheet" },
    { type: "text", value: "\u00b7" },
    { type: "slot", key: "variable", placeholder: "variable" },
    { type: "text", value: "to" },
    { type: "slot", key: "value", placeholder: "value" },
  ],
  add: [
    { type: "verb", value: "Add" },
    { type: "slot", key: "value", placeholder: "value" },
    { type: "text", value: "to" },
    { type: "slot", key: "sheet", placeholder: "sheet" },
    { type: "text", value: "\u00b7" },
    { type: "slot", key: "variable", placeholder: "variable" },
  ],
  subtract: [
    { type: "verb", value: "Subtract" },
    { type: "slot", key: "value", placeholder: "value" },
    { type: "text", value: "from" },
    { type: "slot", key: "sheet", placeholder: "sheet" },
    { type: "text", value: "\u00b7" },
    { type: "slot", key: "variable", placeholder: "variable" },
  ],
  set_true: [
    { type: "verb", value: "Set" },
    { type: "slot", key: "sheet", placeholder: "sheet" },
    { type: "text", value: "\u00b7" },
    { type: "slot", key: "variable", placeholder: "variable" },
    { type: "text", value: "to true" },
  ],
  set_false: [
    { type: "verb", value: "Set" },
    { type: "slot", key: "sheet", placeholder: "sheet" },
    { type: "text", value: "\u00b7" },
    { type: "slot", key: "variable", placeholder: "variable" },
    { type: "text", value: "to false" },
  ],
  toggle: [
    { type: "verb", value: "Toggle" },
    { type: "slot", key: "sheet", placeholder: "sheet" },
    { type: "text", value: "\u00b7" },
    { type: "slot", key: "variable", placeholder: "variable" },
  ],
  clear: [
    { type: "verb", value: "Clear" },
    { type: "slot", key: "sheet", placeholder: "sheet" },
    { type: "text", value: "\u00b7" },
    { type: "slot", key: "variable", placeholder: "variable" },
  ],
};

/**
 * Returns the template for a given operator.
 * Falls back to "set" if unknown.
 */
export function getTemplate(operator) {
  return SENTENCE_TEMPLATES[operator] || SENTENCE_TEMPLATES.set;
}

/**
 * Expands value slot for variable_ref mode.
 * Replaces the single "value" slot with "value_sheet" + "·" + "value".
 */
export function expandTemplateForVariableRef(template) {
  const expanded = [];
  for (const item of template) {
    if (item.type === "slot" && item.key === "value") {
      expanded.push({ type: "slot", key: "value_sheet", placeholder: "sheet" });
      expanded.push({ type: "text", value: "\u00b7" });
      expanded.push({
        type: "slot",
        key: "value",
        placeholder: "variable",
      });
    } else {
      expanded.push(item);
    }
  }
  return expanded;
}

/**
 * Operators that don't need a value input.
 */
export const NO_VALUE_OPERATORS = new Set(["set_true", "set_false", "toggle", "clear"]);

/**
 * Operators available per variable type.
 */
export const OPERATORS_BY_TYPE = {
  number: ["set", "add", "subtract"],
  boolean: ["set_true", "set_false", "toggle"],
  text: ["set", "clear"],
  rich_text: ["set", "clear"],
  select: ["set"],
  multi_select: ["set"],
  date: ["set"],
  reference: ["set"],
};

/**
 * Returns operators for a given variable type.
 */
export function operatorsForType(type) {
  return OPERATORS_BY_TYPE[type] || OPERATORS_BY_TYPE.text;
}

/**
 * The verb that starts each sentence template.
 * Used by the operator selector button.
 */
export const OPERATOR_VERBS = {
  set: "Set",
  add: "Add",
  subtract: "Subtract",
  set_true: "Set",
  set_false: "Set",
  toggle: "Toggle",
  clear: "Clear",
};

/**
 * Descriptive labels for the operator dropdown.
 * Shows the full sentence pattern so the user understands the change.
 */
export const OPERATOR_DROPDOWN_LABELS = {
  set: "Set \u2026 to",
  add: "Add \u2026 to",
  subtract: "Subtract \u2026 from",
  set_true: "Set \u2026 to true",
  set_false: "Set \u2026 to false",
  toggle: "Toggle",
  clear: "Clear",
};

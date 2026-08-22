/**
 * Instruction operator definitions for the instruction builder.
 */

export type InstructionOperator =
  | "set"
  | "add"
  | "subtract"
  | "set_true"
  | "set_false"
  | "toggle"
  | "clear";

export type TemplateItemType = "text" | "slot" | "verb";

export interface TemplateItem {
  type: TemplateItemType;
  value?: string;
  key?: string;
  placeholder?: string;
}

/**
 * Sentence templates for instruction operators.
 * Each template defines the order of elements in a row.
 * - "text" entries are static labels
 * - "slot" entries are interactive (combobox/input)
 * - "verb" entries are the clickable operator selector
 */
const SENTENCE_TEMPLATES: Record<InstructionOperator, TemplateItem[]> = {
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
export function getTemplate(operator: string): TemplateItem[] {
  return SENTENCE_TEMPLATES[operator as InstructionOperator] || SENTENCE_TEMPLATES.set;
}

/**
 * Expands value slot for variable_ref mode.
 * Replaces the single "value" slot with "value_sheet" + "·" + "value".
 */
export function expandTemplateForVariableRef(template: TemplateItem[]): TemplateItem[] {
  const expanded: TemplateItem[] = [];
  for (const item of template) {
    if (item.type === "slot" && item.key === "value") {
      expanded.push({ type: "slot", key: "value_sheet", placeholder: "sheet" });
      expanded.push({ type: "text", value: "\u00b7" });
      expanded.push({ type: "slot", key: "value", placeholder: "variable" });
    } else {
      expanded.push(item);
    }
  }
  return expanded;
}

/**
 * Operators that don't need a value input.
 */
export const NO_VALUE_OPERATORS: Set<InstructionOperator> = new Set([
  "set_true",
  "set_false",
  "toggle",
  "clear",
]);

type VariableType =
  | "number"
  | "boolean"
  | "text"
  | "rich_text"
  | "select"
  | "multi_select"
  | "date"
  | "reference";

/**
 * Operators available per variable type.
 */
export const OPERATORS_BY_TYPE: Record<VariableType, InstructionOperator[]> = {
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
export function operatorsForType(type: string): InstructionOperator[] {
  return OPERATORS_BY_TYPE[type as VariableType] || OPERATORS_BY_TYPE.text;
}

/**
 * All operators in display order.
 */
export const ALL_OPERATORS: InstructionOperator[] = [
  "set",
  "add",
  "subtract",
  "set_true",
  "set_false",
  "toggle",
  "clear",
];

/**
 * Compatible variable types per operator.
 * null means the operator works with all types.
 */
export const TYPES_FOR_OPERATOR: Record<InstructionOperator, VariableType[] | null> = {
  set: null,
  add: ["number"],
  subtract: ["number"],
  set_true: ["boolean"],
  set_false: ["boolean"],
  toggle: ["boolean"],
  clear: ["text", "rich_text"],
};

/**
 * Returns compatible variable types for an operator, or null if all types are accepted.
 */
export function typesForOperator(op: string): VariableType[] | null {
  return TYPES_FOR_OPERATOR[op as InstructionOperator] ?? null;
}

/**
 * The verb that starts each sentence template.
 * Used by the operator selector button.
 */
export const OPERATOR_VERBS: Record<InstructionOperator, string> = {
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
export const OPERATOR_DROPDOWN_LABELS: Record<InstructionOperator, string> = {
  set: "Set \u2026 to",
  add: "Add \u2026 to",
  subtract: "Subtract \u2026 from",
  set_true: "Set \u2026 to true",
  set_false: "Set \u2026 to false",
  toggle: "Toggle",
  clear: "Clear",
};

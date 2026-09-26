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
  /** Literal text that needs no translation (the "·" separator). */
  value?: string;
  /** Translation key of a text item. */
  label?: string;
  key?: string;
  /** Translation key of a slot's placeholder. */
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
    { type: "verb" },
    { type: "slot", key: "sheet", placeholder: "common.condition_builder.placeholders.sheet" },
    { type: "text", value: "\u00b7" },
    {
      type: "slot",
      key: "variable",
      placeholder: "common.condition_builder.placeholders.variable",
    },
    { type: "text", label: "common.instruction_operators.text.set_to" },
    { type: "slot", key: "value", placeholder: "common.condition_builder.placeholders.value" },
  ],
  add: [
    { type: "verb" },
    { type: "slot", key: "value", placeholder: "common.condition_builder.placeholders.value" },
    { type: "text", label: "common.instruction_operators.text.add_to" },
    { type: "slot", key: "sheet", placeholder: "common.condition_builder.placeholders.sheet" },
    { type: "text", value: "\u00b7" },
    {
      type: "slot",
      key: "variable",
      placeholder: "common.condition_builder.placeholders.variable",
    },
  ],
  subtract: [
    { type: "verb" },
    { type: "slot", key: "value", placeholder: "common.condition_builder.placeholders.value" },
    { type: "text", label: "common.instruction_operators.text.subtract_from" },
    { type: "slot", key: "sheet", placeholder: "common.condition_builder.placeholders.sheet" },
    { type: "text", value: "\u00b7" },
    {
      type: "slot",
      key: "variable",
      placeholder: "common.condition_builder.placeholders.variable",
    },
  ],
  set_true: [
    { type: "verb" },
    { type: "slot", key: "sheet", placeholder: "common.condition_builder.placeholders.sheet" },
    { type: "text", value: "\u00b7" },
    {
      type: "slot",
      key: "variable",
      placeholder: "common.condition_builder.placeholders.variable",
    },
    { type: "text", label: "common.instruction_operators.text.to_true" },
  ],
  set_false: [
    { type: "verb" },
    { type: "slot", key: "sheet", placeholder: "common.condition_builder.placeholders.sheet" },
    { type: "text", value: "\u00b7" },
    {
      type: "slot",
      key: "variable",
      placeholder: "common.condition_builder.placeholders.variable",
    },
    { type: "text", label: "common.instruction_operators.text.to_false" },
  ],
  toggle: [
    { type: "verb" },
    { type: "slot", key: "sheet", placeholder: "common.condition_builder.placeholders.sheet" },
    { type: "text", value: "\u00b7" },
    {
      type: "slot",
      key: "variable",
      placeholder: "common.condition_builder.placeholders.variable",
    },
  ],
  clear: [
    { type: "verb" },
    { type: "slot", key: "sheet", placeholder: "common.condition_builder.placeholders.sheet" },
    { type: "text", value: "\u00b7" },
    {
      type: "slot",
      key: "variable",
      placeholder: "common.condition_builder.placeholders.variable",
    },
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
      expanded.push({
        type: "slot",
        key: "value_sheet",
        placeholder: "common.condition_builder.placeholders.sheet",
      });
      expanded.push({ type: "text", value: "\u00b7" });
      expanded.push({
        type: "slot",
        key: "value",
        placeholder: "common.condition_builder.placeholders.variable",
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
 * Translation keys of the verb that starts each sentence template.
 * Used by the operator selector button.
 */
export const OPERATOR_VERB_KEYS: Record<InstructionOperator, string> = {
  set: "common.instruction_operators.verbs.set",
  add: "common.instruction_operators.verbs.add",
  subtract: "common.instruction_operators.verbs.subtract",
  set_true: "common.instruction_operators.verbs.set_true",
  set_false: "common.instruction_operators.verbs.set_false",
  toggle: "common.instruction_operators.verbs.toggle",
  clear: "common.instruction_operators.verbs.clear",
};

/**
 * Translation keys of the operator dropdown labels.
 * Each shows the full sentence pattern so the user understands the change.
 */
export const OPERATOR_DROPDOWN_LABEL_KEYS: Record<InstructionOperator, string> = {
  set: "common.instruction_operators.dropdown.set",
  add: "common.instruction_operators.dropdown.add",
  subtract: "common.instruction_operators.dropdown.subtract",
  set_true: "common.instruction_operators.dropdown.set_true",
  set_false: "common.instruction_operators.dropdown.set_false",
  toggle: "common.instruction_operators.dropdown.toggle",
  clear: "common.instruction_operators.dropdown.clear",
};

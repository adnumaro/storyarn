/**
 * Condition operator definitions for the condition builder.
 * Mirrors Storyarn.Flows.Condition — operators_for_type/1 and operator_label/1.
 */

export type VariableType =
  | "text"
  | "rich_text"
  | "number"
  | "boolean"
  | "select"
  | "multi_select"
  | "date"
  | "reference";

export type ConditionOperator =
  | "equals"
  | "not_equals"
  | "contains"
  | "starts_with"
  | "ends_with"
  | "is_empty"
  | "greater_than"
  | "greater_than_or_equal"
  | "less_than"
  | "less_than_or_equal"
  | "is_true"
  | "is_false"
  | "is_nil"
  | "not_contains"
  | "before"
  | "after";

/**
 * Operators available per variable type.
 * Must stay in sync with Condition.operators_for_type/1.
 */
export const CONDITION_OPERATORS_BY_TYPE: Record<VariableType, ConditionOperator[]> = {
  text: ["equals", "not_equals", "contains", "starts_with", "ends_with", "is_empty"],
  rich_text: ["equals", "not_equals", "contains", "starts_with", "ends_with", "is_empty"],
  number: [
    "equals",
    "not_equals",
    "greater_than",
    "greater_than_or_equal",
    "less_than",
    "less_than_or_equal",
  ],
  boolean: ["is_true", "is_false", "is_nil"],
  select: ["equals", "not_equals", "is_nil"],
  multi_select: ["contains", "not_contains", "is_empty"],
  date: ["equals", "not_equals", "before", "after"],
  reference: ["equals", "not_equals", "is_nil"],
};

/**
 * Translation keys for the condition operator labels.
 * Must stay in sync with Condition.operator_label/1.
 */
export const OPERATOR_LABEL_KEYS: Record<ConditionOperator, string> = {
  equals: "common.condition_operators.equals",
  not_equals: "common.condition_operators.not_equals",
  contains: "common.condition_operators.contains",
  starts_with: "common.condition_operators.starts_with",
  ends_with: "common.condition_operators.ends_with",
  is_empty: "common.condition_operators.is_empty",
  greater_than: "common.condition_operators.greater_than",
  greater_than_or_equal: "common.condition_operators.greater_than_or_equal",
  less_than: "common.condition_operators.less_than",
  less_than_or_equal: "common.condition_operators.less_than_or_equal",
  is_true: "common.condition_operators.is_true",
  is_false: "common.condition_operators.is_false",
  is_nil: "common.condition_operators.is_nil",
  not_contains: "common.condition_operators.not_contains",
  before: "common.condition_operators.before",
  after: "common.condition_operators.after",
};

/**
 * Operators that don't need a value input.
 * Must stay in sync with Condition.operator_requires_value?/1.
 */
export const NO_VALUE_OPERATORS: Set<ConditionOperator> = new Set([
  "is_empty",
  "is_true",
  "is_false",
  "is_nil",
]);

/**
 * Returns operators for a given variable type.
 */
export function operatorsForType(type: string): ConditionOperator[] {
  return CONDITION_OPERATORS_BY_TYPE[type as VariableType] || CONDITION_OPERATORS_BY_TYPE.text;
}

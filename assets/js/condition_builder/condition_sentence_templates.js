/**
 * Operator definitions for the condition builder.
 *
 * Mirrors Storyarn.Flows.Condition — operators_for_type/1 and operator_label/1.
 * Conditions always read left-to-right: sheet · variable operator value,
 * so no sentence template reordering is needed (unlike instructions).
 */

/**
 * Operators available per variable type.
 * Must stay in sync with Condition.operators_for_type/1.
 */
export const CONDITION_OPERATORS_BY_TYPE = {
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
 * Human-readable labels for condition operators.
 * Must stay in sync with Condition.operator_label/1.
 */
export const OPERATOR_LABELS = {
  equals: "equals",
  not_equals: "not equals",
  contains: "contains",
  starts_with: "starts with",
  ends_with: "ends with",
  is_empty: "is empty",
  greater_than: "greater than",
  greater_than_or_equal: "greater than or equal",
  less_than: "less than",
  less_than_or_equal: "less than or equal",
  is_true: "is true",
  is_false: "is false",
  is_nil: "is not set",
  not_contains: "does not contain",
  before: "before",
  after: "after",
};

/**
 * Operators that don't need a value input.
 * Must stay in sync with Condition.operator_requires_value?/1.
 */
export const NO_VALUE_OPERATORS = new Set(["is_empty", "is_true", "is_false", "is_nil"]);

/**
 * Returns operators for a given variable type.
 */
export function operatorsForType(type) {
  return CONDITION_OPERATORS_BY_TYPE[type] || CONDITION_OPERATORS_BY_TYPE.text;
}

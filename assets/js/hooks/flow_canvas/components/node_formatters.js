/**
 * Pure functions for formatting node data for display in StoryarnNode.
 */

/**
 * Returns preview text for a node based on its type and data.
 */
export function getPreviewText(nodeType, nodeData) {
  switch (nodeType) {
    case "dialogue": {
      const textContent = nodeData.text
        ? new DOMParser().parseFromString(nodeData.text, "text/html").body.textContent
        : "";
      return textContent || "";
    }
    case "hub":
      return nodeData.hub_id || "";
    case "condition":
      return getConditionSummary(nodeData);
    case "instruction":
      return nodeData.action || "";
    case "jump":
      return nodeData.target_hub_id ? `→ ${nodeData.target_hub_id}` : "";
    case "exit":
      return nodeData.label || "";
    default:
      return "";
  }
}

/**
 * Returns a human-readable summary of the condition.
 */
export function getConditionSummary(nodeData) {
  const condition = nodeData.condition;
  const switchMode = nodeData.switch_mode;

  if (!condition || !condition.rules || condition.rules.length === 0) {
    return switchMode ? "No conditions" : "No condition";
  }

  const rules = condition.rules;

  if (switchMode) {
    return `${rules.length} output${rules.length > 1 ? "s" : ""} + default`;
  }

  const logic = condition.logic === "all" ? "AND" : "OR";

  if (rules.length === 1) {
    return formatRule(rules[0]);
  }

  return `${rules.length} rules (${logic})`;
}

/**
 * Formats a single rule for display.
 */
export function formatRule(rule) {
  if (!rule.page || !rule.variable) {
    return "Incomplete rule";
  }

  const operatorSymbol = getOperatorSymbol(rule.operator);
  const value = rule.value !== null && rule.value !== undefined ? rule.value : "";

  if (["is_empty", "is_true", "is_false", "is_nil"].includes(rule.operator)) {
    return `${rule.page}.${rule.variable} ${operatorSymbol}`;
  }

  return `${rule.page}.${rule.variable} ${operatorSymbol} ${value}`;
}

/**
 * Formats a rule for short display (used when no label is set).
 */
export function formatRuleShort(rule) {
  if (!rule || !rule.variable) {
    return null;
  }

  const operatorSymbol = getOperatorSymbol(rule.operator);
  const value = rule.value !== null && rule.value !== undefined ? rule.value : "";

  if (["is_empty", "is_true", "is_false", "is_nil"].includes(rule.operator)) {
    return `${rule.variable} ${operatorSymbol}`;
  }

  const truncatedValue = value.length > 10 ? value.substring(0, 10) + "…" : value;
  return `${rule.variable} ${operatorSymbol} ${truncatedValue}`;
}

/**
 * Checks if a rule is complete (has all required fields).
 */
export function isRuleComplete(rule) {
  if (!rule) return false;

  const hasPage = rule.page && rule.page !== "";
  const hasVariable = rule.variable && rule.variable !== "";
  const hasOperator = rule.operator && rule.operator !== "";

  const noValueOperators = ["is_empty", "is_true", "is_false", "is_nil"];
  const needsValue = !noValueOperators.includes(rule.operator);
  const hasValue =
    !needsValue || (rule.value !== null && rule.value !== undefined && rule.value !== "");

  return hasPage && hasVariable && hasOperator && hasValue;
}

/**
 * Returns an error message for an incomplete rule.
 */
export function getRuleErrorMessage(rule) {
  if (!rule) return "Invalid rule";

  const missing = [];

  if (!rule.page || rule.page === "") missing.push("page");
  if (!rule.variable || rule.variable === "") missing.push("variable");
  if (!rule.operator || rule.operator === "") missing.push("operator");

  const noValueOperators = ["is_empty", "is_true", "is_false", "is_nil"];
  if (!noValueOperators.includes(rule.operator)) {
    if (rule.value === null || rule.value === undefined || rule.value === "") {
      missing.push("value");
    }
  }

  if (missing.length === 0) return "";
  return `Incomplete: missing ${missing.join(", ")}`;
}

/**
 * Returns a symbol for the operator.
 */
export function getOperatorSymbol(operator) {
  const symbols = {
    equals: "=",
    not_equals: "≠",
    greater_than: ">",
    greater_than_or_equal: ">=",
    less_than: "<",
    less_than_or_equal: "<=",
    contains: "∋",
    starts_with: "^=",
    ends_with: "$=",
    is_empty: "is empty",
    is_true: "is true",
    is_false: "is false",
    is_nil: "is nil",
    not_contains: "∌",
    before: "<",
    after: ">",
  };
  return symbols[operator] || operator;
}

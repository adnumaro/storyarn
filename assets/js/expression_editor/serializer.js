/**
 * Storyarn Expression Serializer
 *
 * Converts Storyarn structured data back to human-readable DSL text:
 * - Assignments array → multi-line assignment text
 * - Condition object → boolean expression text
 */

// -- Assignment operator mapping --

const ASSIGN_OP_TO_SYMBOL = {
  set: "=",
  add: "+=",
  subtract: "-=",
  set_if_unset: "?=",
};

// -- Condition operator mapping --

const COMPARE_OP_TO_SYMBOL = {
  equals: "==",
  not_equals: "!=",
  greater_than: ">",
  less_than: "<",
  greater_than_or_equal: ">=",
  less_than_or_equal: "<=",
};

// =============================================================================
// serializeAssignments
// =============================================================================

/**
 * Serialize an assignments array to DSL text.
 * @param {Array} assignments - Storyarn assignment objects
 * @returns {string}
 */
export function serializeAssignments(assignments) {
  if (!assignments || !Array.isArray(assignments)) return "";

  return assignments
    .map(serializeOneAssignment)
    .filter((line) => line !== "")
    .join("\n");
}

function serializeOneAssignment(a) {
  const sheet = a.sheet;
  const variable = a.variable;
  if (!sheet || !variable) return "";

  const ref = `${sheet}.${variable}`;
  const operator = a.operator || "set";

  // Special operators with no value
  if (operator === "set_true") return `${ref} = true`;
  if (operator === "set_false") return `${ref} = false`;
  if (operator === "toggle") return `toggle ${ref}`;
  if (operator === "clear") return `clear ${ref}`;

  const symbol = ASSIGN_OP_TO_SYMBOL[operator] || "=";

  // Variable ref value
  if (a.value_type === "variable_ref" && a.value_sheet && a.value) {
    return `${ref} ${symbol} ${a.value_sheet}.${a.value}`;
  }

  // Literal value
  const value = formatAssignmentValue(a.value);
  return `${ref} ${symbol} ${value}`;
}

function formatAssignmentValue(value) {
  if (value === null || value === undefined) return "?";
  const str = String(value);
  if (str === "") return "?";

  // Numeric values stay unquoted
  if (/^-?\d+(\.\d+)?$/.test(str)) return str;

  // Boolean keywords stay unquoted
  if (str === "true" || str === "false") return str;

  // Everything else gets quoted
  return `"${str.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

// =============================================================================
// serializeCondition
// =============================================================================

/**
 * Serialize a condition object to DSL text.
 * Handles both flat format ({logic, rules}) and block format ({logic, blocks}).
 * @param {Object} condition - Storyarn condition
 * @returns {string}
 */
export function serializeCondition(condition) {
  if (!condition) return "";

  // Block format: flatten all rules from blocks/groups
  if (Array.isArray(condition.blocks)) {
    return serializeBlockCondition(condition);
  }

  // Flat format
  const rules = condition.rules;
  if (!rules || !Array.isArray(rules) || rules.length === 0) return "";

  const logic = condition.logic || "all";
  const joiner = logic === "any" ? " || " : " && ";

  return rules
    .map(serializeOneRule)
    .filter((s) => s !== "")
    .join(joiner);
}

function serializeBlockCondition(condition) {
  const blocks = condition.blocks || [];
  if (blocks.length === 0) return "";

  const topLogic = condition.logic || "all";
  const topJoiner = topLogic === "any" ? " || " : " && ";

  const blockTexts = blocks.map((block) => serializeBlock(block)).filter((s) => s !== "");

  return blockTexts.join(topJoiner);
}

function serializeBlock(block) {
  // Groups contain nested blocks
  if (block.type === "group") {
    const innerTexts = (block.blocks || []).map((b) => serializeBlock(b)).filter((s) => s !== "");
    if (innerTexts.length === 0) return "";
    const groupLogic = block.logic || "all";
    const groupJoiner = groupLogic === "any" ? " || " : " && ";
    const inner = innerTexts.join(groupJoiner);
    return innerTexts.length > 1 ? `(${inner})` : inner;
  }

  // Regular block: serialize its rules
  const rules = block.rules || [];
  if (rules.length === 0) return "";

  const blockLogic = block.logic || "all";
  const blockJoiner = blockLogic === "any" ? " || " : " && ";

  const ruleTexts = rules.map(serializeOneRule).filter((s) => s !== "");

  if (ruleTexts.length === 0) return "";
  const text = ruleTexts.join(blockJoiner);
  return ruleTexts.length > 1 ? `(${text})` : text;
}

function serializeOneRule(rule) {
  const sheet = rule.sheet;
  const variable = rule.variable;
  if (!sheet || !variable) return "";

  const ref = `${sheet}.${variable}`;
  const operator = rule.operator || "equals";

  // Boolean operators (no value)
  if (operator === "is_true") return ref;
  if (operator === "is_false") return `!${ref}`;
  if (operator === "is_nil") return `${ref} == nil`;
  if (operator === "is_empty") return `${ref} == ""`;

  // Text operators (function syntax fallback)
  if (operator === "contains") return `contains(${ref}, ${formatConditionValue(rule.value)})`;
  if (operator === "not_contains")
    return `not_contains(${ref}, ${formatConditionValue(rule.value)})`;
  if (operator === "starts_with") return `starts_with(${ref}, ${formatConditionValue(rule.value)})`;
  if (operator === "ends_with") return `ends_with(${ref}, ${formatConditionValue(rule.value)})`;

  const symbol = COMPARE_OP_TO_SYMBOL[operator];
  if (!symbol) return `${ref} ${operator} ${formatConditionValue(rule.value)}`;

  return `${ref} ${symbol} ${formatConditionValue(rule.value)}`;
}

function formatConditionValue(value) {
  if (value === null || value === undefined) return "?";
  const str = String(value);
  if (str === "") return "?";

  // nil keyword
  if (str === "nil") return "nil";

  // Numeric values stay unquoted
  if (/^-?\d+(\.\d+)?$/.test(str)) return str;

  // Boolean keywords stay unquoted
  if (str === "true" || str === "false") return str;

  // Everything else gets quoted
  return `"${str.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

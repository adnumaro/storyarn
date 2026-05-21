/**
 * Serializes condition/instruction data to DSL text for the Code view.
 *
 * Ported from lib/storyarn_web/components/expression_editor.ex
 */

interface ConditionRule {
  sheet: string;
  variable: string;
  operator: string;
  value?: string | number | null;
}

interface ConditionBlock {
  type?: "group" | "block";
  logic?: "any" | "all";
  rules?: ConditionRule[];
  blocks?: ConditionBlock[];
}

interface Condition {
  logic?: "any" | "all";
  blocks?: ConditionBlock[];
}

interface Assignment {
  operator: string;
  sheet: string;
  variable: string;
  value?: string | number | null;
  value_type?: string;
  value_sheet?: string;
}

const OPERATOR_SYMBOLS: Record<string, string> = {
  equals: "==",
  not_equals: "!=",
  greater_than: ">",
  less_than: "<",
  greater_than_or_equal: ">=",
  less_than_or_equal: "<=",
  contains: "contains",
  starts_with: "starts_with",
  ends_with: "ends_with",
  not_contains: "not_contains",
  before: "<",
  after: ">",
};

const INSTRUCTION_SYMBOLS: Record<string, string> = {
  set: "=",
  add: "+=",
  subtract: "-=",
  set_true: "= true",
  set_false: "= false",
  toggle: "toggle",
  clear: "clear",
};

function formatValue(value: string | number | null | undefined): string {
  if (value == null) return "?";
  const str = String(value);
  // If it parses as a number, use it raw
  if (str !== "" && !Number.isNaN(Number(str))) return str;
  // Otherwise quote it
  const escaped = str.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  return `"${escaped}"`;
}

function formatRule(rule: ConditionRule): string {
  const { sheet, variable, operator, value } = rule;
  if (!sheet || !variable) return "";
  const ref = `${sheet}.${variable}`;

  if (operator === "is_true") return ref;
  if (operator === "is_false") return `!${ref}`;
  if (operator === "is_nil") return `${ref} == nil`;
  if (operator === "is_empty") return `${ref} == ""`;

  const symbol = OPERATOR_SYMBOLS[operator] || operator;
  return `${ref} ${symbol} ${formatValue(value)}`;
}

function serializeBlock(block: ConditionBlock): string {
  if (block.type === "group") {
    const joiner = block.logic === "any" ? " || " : " && ";
    const texts = (block.blocks || []).map(serializeBlock).filter(Boolean);
    if (texts.length === 0) return "";
    if (texts.length === 1) return texts[0];
    return `(${texts.join(joiner)})`;
  }

  // Regular block
  const joiner = block.logic === "any" ? " || " : " && ";
  const texts = (block.rules || []).map(formatRule).filter(Boolean);
  if (texts.length === 0) return "";
  if (texts.length === 1) return texts[0];
  return `(${texts.join(joiner)})`;
}

/**
 * Serialize a block-format condition to DSL text.
 */
export function serializeCondition(condition: Condition | null | undefined): string {
  if (!condition) return "";
  const blocks = condition.blocks || [];
  if (blocks.length === 0) return "";

  const topJoiner = condition.logic === "any" ? " || " : " && ";
  return blocks.map(serializeBlock).filter(Boolean).join(topJoiner);
}

/**
 * Serialize an assignments array to DSL text.
 */
export function serializeAssignments(assignments: Assignment[] | null | undefined): string {
  if (!assignments || assignments.length === 0) return "";

  const FIXED_SERIALIZERS: Record<string, (ref: string) => string> = {
    set_true: (ref) => `${ref} = true`,
    set_false: (ref) => `${ref} = false`,
    toggle: (ref) => `toggle ${ref}`,
    clear: (ref) => `clear ${ref}`,
  };

  return assignments
    .map((a) => {
      const { operator, sheet, variable, value, value_type, value_sheet } = a;
      if (!sheet || !variable) return "";
      const ref = `${sheet}.${variable}`;

      const fixedSerializer = FIXED_SERIALIZERS[operator];
      if (fixedSerializer) return fixedSerializer(ref);

      const symbol = INSTRUCTION_SYMBOLS[operator] || "=";
      if (value_type === "variable_ref" && value_sheet && value) {
        return `${ref} ${symbol} ${value_sheet}.${value}`;
      }
      return `${ref} ${symbol} ${formatValue(value)}`;
    })
    .filter(Boolean)
    .join("\n");
}

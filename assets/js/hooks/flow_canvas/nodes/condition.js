/**
 * Condition node type definition.
 *
 * Includes condition-formatting functions (absorbed from node_formatters.js).
 */
import { html } from "lit";
import { GitBranch } from "lucide";
import { createIconSvg } from "../node_config.js";
import { nodeShell, defaultHeader, renderPreview, renderSockets } from "./render_helpers.js";

// --- Condition formatting (was node_formatters.js) ---

function getOperatorSymbol(operator) {
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

function formatRule(rule) {
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

function formatRuleShort(rule) {
  if (!rule || !rule.variable) {
    return null;
  }
  const operatorSymbol = getOperatorSymbol(rule.operator);
  const value = rule.value !== null && rule.value !== undefined ? rule.value : "";
  if (["is_empty", "is_true", "is_false", "is_nil"].includes(rule.operator)) {
    return `${rule.variable} ${operatorSymbol}`;
  }
  const strValue = String(value);
  const truncatedValue = strValue.length > 10 ? strValue.substring(0, 10) + "…" : strValue;
  return `${rule.variable} ${operatorSymbol} ${truncatedValue}`;
}

function isRuleComplete(rule) {
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

function getRuleErrorMessage(rule) {
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

function getConditionSummary(nodeData) {
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

// --- Node definition ---

export default {
  config: {
    label: "Condition",
    color: "#f59e0b",
    icon: createIconSvg(GitBranch),
    inputs: ["input"],
    outputs: ["true", "false"],
    dynamicOutputs: true,
  },

  render(ctx) {
    const { node, nodeData, config, selected, emit } = ctx;
    const preview = this.getPreviewText(nodeData);
    return nodeShell(config.color, selected, html`
      ${defaultHeader(config, config.color, [])}
      ${renderPreview(preview)}
      <div class="content">${renderSockets(node, nodeData, this, emit)}</div>
    `);
  },

  /**
   * Creates dynamic outputs based on switch mode / rules.
   */
  createOutputs(data) {
    if (data.switch_mode && data.condition?.rules?.length > 0) {
      return [...data.condition.rules.map((r) => r.id), "default"];
    }
    return null;
  },

  getPreviewText(data) {
    const summary = getConditionSummary(data);
    if (data.has_stale_refs) {
      return summary ? `\u26A0 ${summary}` : "\u26A0 Stale references";
    }
    return summary;
  },

  formatOutputLabel(key, data) {
    if (data.switch_mode && data.condition?.rules?.length > 0) {
      if (key === "default") return "Default";
      const rule = data.condition.rules.find((r) => r.id === key);
      return rule?.label || formatRuleShort(rule) || key;
    }
    return key === "true" ? "True" : key === "false" ? "False" : key;
  },

  getOutputBadges(key, data) {
    const badges = [];
    if (data.switch_mode && data.condition?.rules?.length > 0 && key !== "default") {
      const rule = data.condition.rules.find((r) => r.id === key);
      if (rule && !isRuleComplete(rule)) {
        badges.push({ type: "error", title: getRuleErrorMessage(rule) });
      }
    }
    return badges;
  },

  needsRebuild(oldData, newData) {
    const oldSwitchMode = oldData?.switch_mode || false;
    const newSwitchMode = newData.switch_mode || false;
    if (oldSwitchMode !== newSwitchMode) return true;
    const oldRules = oldData?.condition?.rules || [];
    const newRules = newData.condition?.rules || [];
    return (
      oldRules.length !== newRules.length || oldRules.some((r, i) => r.id !== newRules[i]?.id)
    );
  },
};

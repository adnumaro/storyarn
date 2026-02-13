/**
 * Condition builder core — reusable rendering logic for condition UI.
 *
 * Used by both the ConditionBuilder LiveView hook (flow editor) and the
 * Conditional TipTap NodeView (screenplay editor). Accepts a pushEvent
 * callback instead of relying on a LiveView hook directly.
 */

import { createElement, Plus } from "lucide";
import { createConditionRuleRow } from "../../condition_builder/condition_rule_row";
import { OPERATOR_LABELS as DEFAULT_OPERATOR_LABELS } from "../../condition_builder/condition_sentence_templates";
import { groupVariablesBySheet } from "./utils.js";

const DEFAULT_TRANSLATIONS = {
  operator_labels: DEFAULT_OPERATOR_LABELS,
  match: "Match",
  all: "all",
  any: "any",
  of_the_rules: "of the rules",
  switch_mode_info: "Each condition creates an output. First match wins.",
  add_condition: "Add condition",
  no_conditions: "No conditions set",
  placeholder_sheet: "sheet",
  placeholder_variable: "variable",
  placeholder_operator: "op",
  placeholder_value: "value",
  placeholder_label: "label",
};

/**
 * Create a condition builder UI inside the given container.
 *
 * @param {Object} opts
 * @param {HTMLElement} opts.container - DOM element to render into
 * @param {Object} opts.condition - Initial condition ({logic, rules})
 * @param {Array} opts.variables - Flat variable list
 * @param {boolean} opts.canEdit - Whether editing is allowed
 * @param {boolean} [opts.switchMode=false] - Switch mode (each rule = an output)
 * @param {Object} opts.context - Context map for event payload (element-id, choice-id, etc.)
 * @param {string} opts.eventName - Event name to push
 * @param {Function} opts.pushEvent - Callback: pushEvent(eventName, payload)
 * @param {Object} [opts.translations] - Optional translation overrides
 * @returns {{ destroy: Function, update: Function }}
 */
export function createConditionBuilder({
  container,
  condition,
  variables,
  canEdit,
  switchMode = false,
  context,
  eventName,
  pushEvent,
  translations,
}) {
  let currentCondition = condition || { logic: "all", rules: [] };
  const sheetsWithVariables = groupVariablesBySheet(variables || []);
  let rows = [];
  let addButton = null;

  const t = {
    ...DEFAULT_TRANSLATIONS,
    ...translations,
    operator_labels: {
      ...DEFAULT_OPERATOR_LABELS,
      ...(translations?.operator_labels || {}),
    },
  };

  function push() {
    pushEvent(eventName, {
      condition: currentCondition,
      ...context,
    });
  }

  function destroyRows() {
    rows.forEach((row) => row.destroy?.());
    rows = [];
  }

  function render() {
    destroyRows();
    container.innerHTML = "";

    const rules = currentCondition.rules || [];

    // Logic toggle (only show when 2+ rules AND not in switch mode)
    if (rules.length >= 2 && !switchMode) {
      container.appendChild(renderLogicToggle());
    }

    // Switch mode info
    if (switchMode && rules.length > 0) {
      const info = document.createElement("p");
      info.className = "text-xs text-base-content/60 mb-2";
      info.textContent = t.switch_mode_info;
      container.appendChild(info);
    }

    // Rule rows
    const rowsContainer = document.createElement("div");
    rowsContainer.className = "space-y-0";
    container.appendChild(rowsContainer);

    rules.forEach((rule, index) => {
      const rowEl = document.createElement("div");
      rowsContainer.appendChild(rowEl);

      const row = createConditionRuleRow({
        container: rowEl,
        rule,
        variables: variables || [],
        sheetsWithVariables,
        canEdit,
        switchMode,
        translations: t,
        onChange: (updatedRule) => {
          currentCondition.rules[index] = updatedRule;
          push();
        },
        onRemove: () => {
          currentCondition.rules.splice(index, 1);
          push();
          render();
        },
        onAdvance: () => {
          const nextRow = rows[index + 1];
          if (nextRow) {
            nextRow.focusFirstEmpty();
          } else if (addButton) {
            addButton.focus();
          }
        },
      });

      rows.push(row);
    });

    // Add rule button
    if (canEdit) {
      const addBtn = document.createElement("button");
      addBtn.type = "button";
      addBtn.className =
        "btn btn-ghost btn-xs gap-1 border border-dashed border-base-300 mt-2";
      addBtn.appendChild(createElement(Plus, { width: 12, height: 12 }));
      addBtn.append(` ${t.add_condition}`);
      addBtn.addEventListener("click", () => {
        const newRule = {
          id: `rule_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
          sheet: null,
          variable: null,
          operator: "equals",
          value: null,
        };
        if (switchMode) {
          newRule.label = "";
        }
        currentCondition.rules.push(newRule);
        push();
        render();

        requestAnimationFrame(() => {
          const lastRow = rows[rows.length - 1];
          if (lastRow) lastRow.focusFirstEmpty();
        });
      });

      addButton = addBtn;
      container.appendChild(addBtn);
    }

    // Empty state
    if (rules.length === 0 && !canEdit) {
      const empty = document.createElement("p");
      empty.className = "text-xs text-base-content/50 italic";
      empty.textContent = t.no_conditions;
      container.appendChild(empty);
    }
  }

  function renderLogicToggle() {
    const wrapper = document.createElement("div");
    wrapper.className = "flex items-center gap-2 text-xs mb-2";

    const matchLabel = document.createElement("span");
    matchLabel.className = "text-base-content/60";
    matchLabel.textContent = t.match;
    wrapper.appendChild(matchLabel);

    const joinDiv = document.createElement("div");
    joinDiv.className = "join";

    const allBtn = document.createElement("button");
    allBtn.type = "button";
    allBtn.className = `join-item btn btn-xs ${currentCondition.logic === "all" ? "btn-active" : ""}`;
    allBtn.textContent = t.all;
    allBtn.disabled = !canEdit;
    allBtn.addEventListener("click", () => {
      currentCondition.logic = "all";
      push();
      render();
    });

    const anyBtn = document.createElement("button");
    anyBtn.type = "button";
    anyBtn.className = `join-item btn btn-xs ${currentCondition.logic === "any" ? "btn-active" : ""}`;
    anyBtn.textContent = t.any;
    anyBtn.disabled = !canEdit;
    anyBtn.addEventListener("click", () => {
      currentCondition.logic = "any";
      push();
      render();
    });

    joinDiv.appendChild(allBtn);
    joinDiv.appendChild(anyBtn);
    wrapper.appendChild(joinDiv);

    const ofLabel = document.createElement("span");
    ofLabel.className = "text-base-content/60";
    ofLabel.textContent = t.of_the_rules;
    wrapper.appendChild(ofLabel);

    return wrapper;
  }

  // Initial render
  render();

  return {
    destroy() {
      destroyRows();
      container.innerHTML = "";
    },
    update(newCondition) {
      currentCondition = newCondition || { logic: "all", rules: [] };
      render();
    },
  };
}

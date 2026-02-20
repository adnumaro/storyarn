/**
 * Condition block card component.
 *
 * Renders a single condition block containing rule rows, a block-level AND/OR
 * toggle (when 2+ rules and not in switch mode), and add/remove controls.
 * In switch mode, a label input is shown at the top.
 *
 * Re-uses createConditionRuleRow() for leaf rule rendering — no duplication.
 */

import { createElement, Plus, X } from "lucide";
import { createConditionRuleRow } from "./condition_rule_row";
import { createLogicToggle, generateId } from "./condition_utils";

/**
 * @param {Object} opts
 * @param {HTMLElement} opts.container - DOM element to render into
 * @param {Object} opts.block - Block data {id, type, logic, rules, label?}
 * @param {Array} opts.variables - All project variables
 * @param {Array} opts.sheetsWithVariables - Grouped sheets
 * @param {boolean} opts.canEdit - Whether editing is allowed
 * @param {boolean} opts.switchMode - Whether in switch mode
 * @param {Object} opts.translations - Translated strings
 * @param {Function} opts.onChange - Callback: (updatedBlock) => void
 * @param {Function} opts.onRemove - Callback: () => void
 * @returns {{ getBlock: Function, destroy: Function }}
 */
export function createConditionBlock(opts) {
  const {
    container,
    block,
    variables,
    sheetsWithVariables,
    canEdit,
    switchMode,
    translations: t,
    onChange,
    onRemove,
  } = opts;

  let currentBlock = { ...block, rules: [...(block.rules || [])] };
  let rows = [];

  render();

  function render() {
    destroyRows();
    container.innerHTML = "";
    container.className = "condition-block rounded-lg border border-base-300/60 bg-base-100 p-2";

    // Header row: label (switch mode) + remove button
    const header = document.createElement("div");
    header.className = "flex items-center justify-between mb-1";

    if (switchMode && canEdit) {
      const labelInput = document.createElement("input");
      labelInput.type = "text";
      labelInput.maxLength = 100;
      labelInput.className =
        "input input-xs input-bordered w-full max-w-[200px] font-medium";
      labelInput.placeholder = t?.placeholder_label || "label";
      labelInput.value = currentBlock.label || "";
      labelInput.addEventListener("input", () => {
        currentBlock.label = labelInput.value;
      });
      labelInput.addEventListener("blur", () => notifyChange());
      labelInput.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          notifyChange();
        }
      });
      header.appendChild(labelInput);
    } else if (switchMode) {
      const labelSpan = document.createElement("span");
      labelSpan.className = "text-xs font-medium";
      labelSpan.textContent = currentBlock.label || t?.placeholder_label || "label";
      header.appendChild(labelSpan);
    } else {
      // Spacer
      header.appendChild(document.createElement("span"));
    }

    if (canEdit) {
      const removeBtn = document.createElement("button");
      removeBtn.type = "button";
      removeBtn.className =
        "btn btn-ghost btn-xs btn-square opacity-0 group-hover/block:opacity-100 transition-opacity";
      removeBtn.appendChild(createElement(X, { width: 12, height: 12 }));
      removeBtn.title = "Remove block";
      removeBtn.addEventListener("click", () => {
        if (onRemove) onRemove();
      });
      header.appendChild(removeBtn);
    }

    container.appendChild(header);
    container.classList.add("group/block");

    const rules = currentBlock.rules || [];

    // Block-level AND/OR toggle (only for 2+ rules, not switch mode)
    if (rules.length >= 2 && !switchMode) {
      const toggle = createLogicToggle({
        logic: currentBlock.logic,
        canEdit,
        ofLabel: t?.of_the_rules || "of the rules",
        translations: t,
        onChange: (newLogic) => {
          currentBlock.logic = newLogic;
          notifyChange();
          render();
        },
      });
      toggle.classList.add("mb-1");
      container.appendChild(toggle);
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
        switchMode: false, // Label is on the block, not on individual rules
        translations: t,
        onChange: (updatedRule) => {
          currentBlock.rules[index] = updatedRule;
          notifyChange();
        },
        onRemove: () => {
          currentBlock.rules.splice(index, 1);
          notifyChange();
          render();
        },
        onAdvance: () => {
          const nextRow = rows[index + 1];
          if (nextRow) {
            nextRow.focusFirstEmpty();
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
        "btn btn-ghost btn-xs gap-1 border border-dashed border-base-300 mt-1 w-full";
      addBtn.appendChild(createElement(Plus, { width: 12, height: 12 }));
      addBtn.append(` ${t?.add_condition || "Add rule"}`);
      addBtn.addEventListener("click", () => {
        const newRule = {
          id: generateId("rule"),
          sheet: null,
          variable: null,
          operator: "equals",
          value: null,
        };
        currentBlock.rules.push(newRule);
        notifyChange();
        render();

        requestAnimationFrame(() => {
          const lastRow = rows[rows.length - 1];
          if (lastRow) lastRow.focusFirstEmpty();
        });
      });
      container.appendChild(addBtn);
    }

    // Empty state
    if (rules.length === 0 && !canEdit) {
      const empty = document.createElement("p");
      empty.className = "text-xs text-base-content/50 italic";
      empty.textContent = t?.no_conditions || "No conditions set";
      container.appendChild(empty);
    }
  }

  function destroyRows() {
    rows.forEach((row) => row.destroy?.());
    rows = [];
  }

  function notifyChange() {
    if (onChange) onChange({ ...currentBlock, rules: [...currentBlock.rules] });
  }

  return {
    getBlock: () => ({ ...currentBlock, rules: [...currentBlock.rules] }),
    destroy: () => {
      destroyRows();
      container.innerHTML = "";
    },
  };
}

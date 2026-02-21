/**
 * Renders one sentence-flow condition rule row.
 *
 * Each row reads like a sentence: "sheet · variable operator value".
 * Mirrors assignment_row.js but adapted for condition semantics:
 * - Operator is a combobox (conditions have many operators per type)
 * - No value_type toggle (conditions compare against literals only)
 * - In switch mode: prepends a free-text label input (output name)
 * - Value slot varies by type: select options combobox, free-text for
 *   number/text/date, hidden for no-value operators
 *
 * Cascade: sheet → clears variable/operator/value,
 *          variable → auto-sets operator/clears value
 */

import { ArrowRight, createElement, X } from "lucide";
import { createCombobox } from "../instruction_builder/combobox";
import {
  OPERATOR_LABELS as DEFAULT_OPERATOR_LABELS,
  NO_VALUE_OPERATORS,
  operatorsForType,
} from "./condition_sentence_templates";

/**
 * Creates and renders a condition rule row.
 *
 * @param {Object} opts
 * @param {HTMLElement} opts.container - Row container element
 * @param {Object} opts.rule - Rule data {id, sheet, variable, operator, value, label?}
 * @param {Array} opts.variables - All project variables
 * @param {Array} opts.sheetsWithVariables - Grouped sheets [{shortcut, name, vars}]
 * @param {boolean} opts.canEdit - Whether editing is allowed
 * @param {boolean} opts.switchMode - Whether in switch mode (show label input)
 * @param {Object} opts.translations - Translated strings from backend
 * @param {Function} opts.onChange - Callback when rule changes: (updatedRule) => void
 * @param {Function} opts.onRemove - Callback to remove this row: () => void
 * @param {Function} opts.onAdvance - Callback to advance to next row: () => void
 */
export function createConditionRuleRow(opts) {
  const {
    container,
    rule,
    variables,
    sheetsWithVariables,
    canEdit,
    switchMode,
    translations: t,
    onChange,
    onRemove,
    onAdvance,
  } = opts;

  const operatorLabels = t?.operator_labels || DEFAULT_OPERATOR_LABELS;

  const currentRule = { ...rule };
  let comboboxes = {};

  render();

  function render() {
    destroyComboboxes();
    container.innerHTML = "";
    container.className = "condition-rule-row group";

    const sentenceWrap = document.createElement("div");
    sentenceWrap.className = "flex flex-wrap items-baseline gap-1 flex-1";

    // Switch mode: label input first
    if (switchMode) {
      const labelWrap = document.createElement("span");
      labelWrap.className = "inline-flex items-baseline gap-1";

      const arrow = document.createElement("span");
      arrow.className = "sentence-text";
      arrow.appendChild(createElement(ArrowRight, { width: 12, height: 12 }));
      labelWrap.appendChild(arrow);

      const labelInput = document.createElement("input");
      labelInput.type = "text";
      labelInput.className = "sentence-slot";
      labelInput.placeholder = t?.placeholder_label || "label";
      labelInput.value = currentRule.label || "";
      labelInput.disabled = !canEdit;
      labelInput.autocomplete = "off";
      labelInput.spellcheck = false;
      adjustInputWidth(labelInput);
      if (currentRule.label) labelInput.classList.add("filled");

      labelInput.addEventListener("input", () => {
        adjustInputWidth(labelInput);
        currentRule.label = labelInput.value;
        labelInput.classList.toggle("filled", !!labelInput.value);
      });
      labelInput.addEventListener("blur", () => {
        notifyChange();
      });
      labelInput.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          notifyChange();
        }
      });

      labelWrap.appendChild(labelInput);

      const colon = document.createElement("span");
      colon.className = "sentence-text";
      colon.textContent = ":";
      labelWrap.appendChild(colon);

      sentenceWrap.appendChild(labelWrap);
    }

    // Sheet combobox
    const sheetContainer = document.createElement("span");
    sheetContainer.className = "inline-block relative";
    comboboxes.sheet = createCombobox({
      container: sheetContainer,
      options: sheetsWithVariables.map((p) => ({
        value: p.shortcut,
        label: p.name,
        displayValue: p.shortcut,
        meta: p.shortcut,
      })),
      value: currentRule.sheet || "",
      displayValue: currentRule.sheet || "",
      placeholder: t?.placeholder_sheet || "sheet",
      disabled: !canEdit,
      freeText: false,
      onSelect: (option) => handleSlotChange("sheet", option),
    });
    sentenceWrap.appendChild(sheetContainer);

    // Separator
    const dot1 = document.createElement("span");
    dot1.className = "sentence-text";
    dot1.textContent = "\u00b7";
    sentenceWrap.appendChild(dot1);

    // Variable combobox
    const variableContainer = document.createElement("span");
    variableContainer.className = "inline-block relative";
    const variableOptions = getVariableOptions();
    comboboxes.variable = createCombobox({
      container: variableContainer,
      options: variableOptions,
      value: currentRule.variable || "",
      displayValue: currentRule.variable || "",
      placeholder: t?.placeholder_variable || "variable",
      disabled: !canEdit || !currentRule.sheet,
      freeText: false,
      onSelect: (option) => handleSlotChange("variable", option),
    });
    sentenceWrap.appendChild(variableContainer);

    // Operator combobox
    const varType = getVariableType();
    const availableOps = varType ? operatorsForType(varType) : [];
    const operatorContainer = document.createElement("span");
    operatorContainer.className = "inline-block relative";
    const opOptions = availableOps.map((op) => ({
      value: op,
      label: operatorLabels[op] || op,
    }));
    comboboxes.operator = createCombobox({
      container: operatorContainer,
      options: opOptions,
      value: currentRule.operator || "",
      displayValue: operatorLabels[currentRule.operator] || currentRule.operator || "",
      placeholder: t?.placeholder_operator || "op",
      disabled: !canEdit || !currentRule.variable,
      freeText: false,
      onSelect: (option) => handleSlotChange("operator", option),
    });
    sentenceWrap.appendChild(operatorContainer);

    // Value slot (varies by operator and type)
    const operator = currentRule.operator || "equals";
    if (!NO_VALUE_OPERATORS.has(operator)) {
      const valueContainer = document.createElement("span");
      valueContainer.className = "inline-block relative";
      const valueOptions = getValueOptions();
      const isFreeText = valueOptions.length === 0;

      comboboxes.value = createCombobox({
        container: valueContainer,
        options: valueOptions,
        value: currentRule.value || "",
        displayValue: currentRule.value || "",
        placeholder: t?.placeholder_value || "value",
        disabled: !canEdit || !currentRule.operator,
        freeText: isFreeText,
        onSelect: (option) => handleSlotChange("value", option),
      });
      sentenceWrap.appendChild(valueContainer);
    }

    container.appendChild(sentenceWrap);

    // Remove button (visible on hover)
    if (canEdit) {
      const removeBtn = document.createElement("button");
      removeBtn.type = "button";
      removeBtn.className = "sp-row-action sp-row-action-danger";
      removeBtn.appendChild(createElement(X, { width: 12, height: 12 }));
      removeBtn.title = "Remove";
      removeBtn.addEventListener("click", () => {
        if (onRemove) onRemove();
      });
      container.appendChild(removeBtn);
    }
  }

  function destroyComboboxes() {
    Object.values(comboboxes).forEach((cb) => {
      cb.destroy?.();
    });
    comboboxes = {};
  }

  function getVariableOptions() {
    const sheetShortcut = currentRule.sheet;
    if (!sheetShortcut) return [];
    const sheet = sheetsWithVariables.find((p) => p.shortcut === sheetShortcut);
    if (!sheet) return [];
    return sheet.vars.map((v) => ({
      value: v.variable_name,
      label: v.variable_name,
      group: v.table_name ? v.table_name.toUpperCase() : null,
      meta: v.block_type,
      blockType: v.block_type,
      options: v.options,
    }));
  }

  function getValueOptions() {
    // For select/multi_select types, show the options as a combobox
    const selectedVar = findVariable(variables, currentRule.sheet, currentRule.variable);
    if (
      selectedVar &&
      (selectedVar.block_type === "select" || selectedVar.block_type === "multi_select") &&
      selectedVar.options
    ) {
      return selectedVar.options.map((opt) => ({
        value: opt.key,
        label: opt.value || opt.key,
      }));
    }
    return [];
  }

  function getVariableType() {
    const v = findVariable(variables, currentRule.sheet, currentRule.variable);
    return v ? v.block_type : null;
  }

  function handleSlotChange(key, option) {
    currentRule[key] = option.value;

    if (key === "sheet") {
      currentRule.variable = null;
      currentRule.operator = "equals";
      currentRule.value = null;
      notifyChange();
      requestAnimationFrame(() => {
        render();
        if (comboboxes.variable) comboboxes.variable.focus();
      });
      return;
    }

    if (key === "variable") {
      // Auto-detect type and set first operator
      const selectedVar = findVariable(variables, currentRule.sheet, option.value);
      if (selectedVar) {
        const ops = operatorsForType(selectedVar.block_type);
        if (ops.length > 0) {
          currentRule.operator = ops[0];
        }
      }
      currentRule.value = null;
      notifyChange();
      requestAnimationFrame(() => {
        render();
        const op = currentRule.operator;
        if (NO_VALUE_OPERATORS.has(op)) {
          if (onAdvance) onAdvance();
        } else if (comboboxes.operator) {
          comboboxes.operator.focus();
        }
      });
      return;
    }

    if (key === "operator") {
      // Clear value when switching between value/no-value operators
      const oldOp = rule.operator || "equals";
      if (NO_VALUE_OPERATORS.has(option.value) !== NO_VALUE_OPERATORS.has(oldOp)) {
        currentRule.value = null;
      }
      notifyChange();
      requestAnimationFrame(() => {
        render();
        if (NO_VALUE_OPERATORS.has(option.value)) {
          if (onAdvance) onAdvance();
        } else if (comboboxes.value) {
          comboboxes.value.focus();
        }
      });
      return;
    }

    if (key === "value") {
      notifyChange();
      if (option.confirmed && onAdvance) onAdvance();
      return;
    }

    notifyChange();
  }

  function notifyChange() {
    if (onChange) onChange({ ...currentRule });
  }

  function findVariable(vars, sheetShortcut, variableName) {
    if (!sheetShortcut || !variableName) return null;
    return vars.find((v) => v.sheet_shortcut === sheetShortcut && v.variable_name === variableName);
  }

  // Public API
  return {
    getRule: () => ({ ...currentRule }),
    focusFirstEmpty: () => {
      for (const key of ["sheet", "variable", "operator", "value"]) {
        if (!currentRule[key] && comboboxes[key]) {
          comboboxes[key].focus();
          return;
        }
      }
    },
    destroy: () => {
      destroyComboboxes();
      container.innerHTML = "";
    },
  };
}

/**
 * Auto-adjusts input width to fit its content.
 */
function adjustInputWidth(input) {
  const minWidth = 3;
  const text = input.value || input.placeholder || "";
  const charCount = Math.max(text.length, minWidth);
  input.style.width = `${charCount + 2}ch`;
}

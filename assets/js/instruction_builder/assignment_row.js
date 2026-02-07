/**
 * Renders one sentence-flow assignment row.
 *
 * Each row reads like a sentence (e.g., "Set mc.jaime . health to 100").
 * Static words are plain text, interactive parts are combobox inputs.
 * The operator verb (first word) is clickable when multiple operators
 * are available for the selected variable's type.
 */

import { createCombobox } from "./combobox";
import {
  getTemplate,
  expandTemplateForVariableRef,
  NO_VALUE_OPERATORS,
  operatorsForType,
  OPERATOR_VERBS,
  OPERATOR_DROPDOWN_LABELS,
} from "./sentence_templates";

/**
 * Creates and renders an assignment row.
 *
 * @param {Object} opts
 * @param {HTMLElement} opts.container - Row container element
 * @param {Object} opts.assignment - Assignment data
 * @param {Array} opts.variables - All project variables
 * @param {Array} opts.sheetsWithVariables - Grouped sheets [{shortcut, name, vars}]
 * @param {boolean} opts.canEdit - Whether editing is allowed
 * @param {Function} opts.onChange - Callback when assignment changes: (updatedAssignment) => void
 * @param {Function} opts.onRemove - Callback to remove this row: () => void
 * @param {Object} opts.translations - Translated strings from backend
 * @param {Function} opts.onAdvance - Callback to advance to next row or add button: () => void
 */
export function createAssignmentRow(opts) {
  const {
    container,
    assignment,
    variables,
    sheetsWithVariables,
    canEdit,
    translations: t,
    onChange,
    onRemove,
    onAdvance,
  } = opts;

  let currentAssignment = { ...assignment };
  let comboboxes = {};
  let operatorDropdownCleanup = null;

  render();

  function render() {
    // Destroy existing comboboxes first (cleans up body-appended dropdowns)
    destroyComboboxes();
    cleanupOperatorDropdown();

    container.innerHTML = "";
    container.className = "assignment-row group";

    const sentenceWrap = document.createElement("div");
    sentenceWrap.className = "flex flex-wrap items-baseline gap-1 flex-1";

    const operator = currentAssignment.operator || "set";
    let template = getTemplate(operator);

    // Expand value slot for variable_ref if the operator requires a value
    const hasValueSlot = template.some(
      (t) => t.type === "slot" && t.key === "value",
    );
    if (
      hasValueSlot &&
      currentAssignment.value_type === "variable_ref" &&
      !NO_VALUE_OPERATORS.has(operator)
    ) {
      template = expandTemplateForVariableRef(template);
    }

    // Track slot order for auto-advance
    const slotKeys = template
      .filter((t) => t.type === "slot")
      .map((t) => t.key);

    // Check if operator selector should be shown
    const varType = getVariableType();
    const availableOps = varType ? operatorsForType(varType) : [];
    const showOperatorSelector = canEdit && availableOps.length > 1;

    // Render each template element
    for (const item of template) {
      if (item.type === "verb") {
        if (showOperatorSelector) {
          // Render clickable operator selector instead of plain text
          const opEl = createOperatorSelector(availableOps);
          sentenceWrap.appendChild(opEl);
        } else {
          const span = document.createElement("span");
          span.className = "sentence-text";
          // Use translated verb if available
          const verbKey = currentAssignment.operator || "set";
          span.textContent = t?.operator_verbs?.[verbKey] || item.value;
          sentenceWrap.appendChild(span);
        }
      } else if (item.type === "text") {
        const span = document.createElement("span");
        span.className = "sentence-text";
        span.textContent = t?.sentence_texts?.[item.value] || item.value;
        sentenceWrap.appendChild(span);
      } else if (item.type === "slot") {
        const slotContainer = document.createElement("span");
        slotContainer.className = "inline-block relative";
        const placeholderKey = `placeholder_${item.key}`;
        const placeholder = t?.[placeholderKey] || item.placeholder;
        const combobox = createSlotCombobox(
          item.key,
          placeholder,
          slotContainer,
          slotKeys,
        );
        comboboxes[item.key] = combobox;
        sentenceWrap.appendChild(slotContainer);
      }
    }

    // Value type toggle (only for operators that require a value)
    if (!NO_VALUE_OPERATORS.has(operator) && canEdit) {
      const valueSlotEl =
        comboboxes.value_sheet?.input?.parentElement ||
        comboboxes.value?.input?.parentElement;
      if (valueSlotEl) {
        const toggle = createValueTypeToggle();
        sentenceWrap.insertBefore(toggle, valueSlotEl);
      }
    }

    container.appendChild(sentenceWrap);

    // Remove button (visible on hover)
    if (canEdit) {
      const removeBtn = document.createElement("button");
      removeBtn.type = "button";
      removeBtn.className =
        "btn btn-ghost btn-xs btn-square text-error opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0 self-center";
      removeBtn.innerHTML =
        '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>';
      removeBtn.title = "Remove";
      removeBtn.addEventListener("click", () => {
        if (onRemove) onRemove();
      });
      container.appendChild(removeBtn);
    }
  }

  function destroyComboboxes() {
    Object.values(comboboxes).forEach((cb) => cb.destroy?.());
    comboboxes = {};
  }

  function cleanupOperatorDropdown() {
    if (operatorDropdownCleanup) {
      operatorDropdownCleanup();
      operatorDropdownCleanup = null;
    }
  }

  function createSlotCombobox(key, placeholder, slotContainer, slotKeys) {
    const options = getOptionsForSlot(key);
    const currentVal = currentAssignment[key] || "";
    const displayVal = getDisplayValueForSlot(key, currentVal);

    const isFreeText =
      key === "value" && currentAssignment.value_type !== "variable_ref";

    const combobox = createCombobox({
      container: slotContainer,
      options,
      value: currentVal,
      displayValue: displayVal,
      placeholder,
      disabled: !canEdit || isSlotDisabled(key),
      freeText: isFreeText,
      onSelect: (option) => {
        handleSlotChange(key, option, slotKeys);
      },
    });

    return combobox;
  }

  function getOptionsForSlot(key) {
    switch (key) {
      case "sheet":
      case "value_sheet":
        return sheetsWithVariables.map((p) => ({
          value: p.shortcut,
          label: p.name,
          displayValue: p.shortcut,
          meta: p.shortcut,
        }));

      case "variable": {
        const sheetShortcut = currentAssignment.sheet;
        if (!sheetShortcut) return [];
        const sheet = sheetsWithVariables.find(
          (p) => p.shortcut === sheetShortcut,
        );
        if (!sheet) return [];
        return sheet.vars.map((v) => ({
          value: v.variable_name,
          label: v.variable_name,
          meta: v.block_type,
          blockType: v.block_type,
          options: v.options,
        }));
      }

      case "value": {
        // When value_type is variable_ref, show variables from value_sheet
        if (currentAssignment.value_type === "variable_ref") {
          const vs = currentAssignment.value_sheet;
          if (!vs) return [];
          const sheet = sheetsWithVariables.find((p) => p.shortcut === vs);
          if (!sheet) return [];
          return sheet.vars.map((v) => ({
            value: v.variable_name,
            label: v.variable_name,
            meta: v.block_type,
          }));
        }
        // Literal mode: check if it's a select type, show options
        const selectedVar = findVariable(
          variables,
          currentAssignment.sheet,
          currentAssignment.variable,
        );
        if (
          selectedVar &&
          (selectedVar.block_type === "select" ||
            selectedVar.block_type === "multi_select") &&
          selectedVar.options
        ) {
          return selectedVar.options.map((opt) => ({
            value: opt.key,
            label: opt.value || opt.key,
          }));
        }
        return [];
      }

      default:
        return [];
    }
  }

  function getDisplayValueForSlot(key, val) {
    if (!val) return "";
    return val;
  }

  function isSlotDisabled(key) {
    switch (key) {
      case "variable":
        return !currentAssignment.sheet;
      case "value":
        if (currentAssignment.value_type === "variable_ref") {
          return !currentAssignment.value_sheet;
        }
        return !currentAssignment.variable;
      case "value_sheet":
        return !currentAssignment.variable;
      default:
        return false;
    }
  }

  function handleSlotChange(key, option, slotKeys) {
    currentAssignment[key] = option.value;

    if (key === "sheet") {
      currentAssignment.variable = null;
      currentAssignment.operator = "set";
      currentAssignment.value = null;
      currentAssignment.value_sheet = null;
      notifyChange();
      // Defer re-render to next frame so the current combobox event finishes
      requestAnimationFrame(() => {
        render();
        if (comboboxes.variable) comboboxes.variable.focus();
      });
      return;
    }

    if (key === "variable") {
      // Auto-detect type and set first operator
      const selectedVar = findVariable(
        variables,
        currentAssignment.sheet,
        option.value,
      );
      if (selectedVar) {
        const ops = operatorsForType(selectedVar.block_type);
        if (ops.length > 0) {
          currentAssignment.operator = ops[0];
        }
      }
      currentAssignment.value = null;
      currentAssignment.value_sheet = null;
      notifyChange();
      requestAnimationFrame(() => {
        render();
        const op = currentAssignment.operator;
        if (NO_VALUE_OPERATORS.has(op)) {
          if (onAdvance) onAdvance();
        } else if (comboboxes.value) {
          comboboxes.value.focus();
        }
      });
      return;
    }

    if (key === "value_sheet") {
      currentAssignment.value = null;
      notifyChange();
      requestAnimationFrame(() => {
        render();
        if (comboboxes.value) comboboxes.value.focus();
      });
      return;
    }

    if (key === "value") {
      notifyChange();
      // Only advance when the user explicitly confirmed (Enter or dropdown click)
      // NOT on blur (which has confirmed: false)
      if (option.confirmed && onAdvance) onAdvance();
      return;
    }

    notifyChange();
  }

  function createOperatorSelector(availableOps) {
    const wrapper = document.createElement("span");
    wrapper.className = "operator-selector-wrapper";

    const currentOp = currentAssignment.operator || "set";
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "operator-selector";
    btn.textContent = t?.operator_verbs?.[currentOp] || OPERATOR_VERBS[currentOp] || currentOp;
    btn.title = "Change operator";

    const dropdown = document.createElement("div");
    dropdown.className = "operator-dropdown hidden";

    for (const op of availableOps) {
      const optEl = document.createElement("div");
      optEl.className = "operator-option";
      if (op === currentOp) optEl.classList.add("active");
      optEl.textContent = t?.operator_dropdown_labels?.[op] || OPERATOR_DROPDOWN_LABELS[op] || op;
      optEl.addEventListener("mousedown", (e) => {
        e.preventDefault();
        e.stopPropagation();
        const oldOp = currentAssignment.operator;
        currentAssignment.operator = op;
        // Clear value when switching between value/no-value operators
        if (NO_VALUE_OPERATORS.has(op) !== NO_VALUE_OPERATORS.has(oldOp)) {
          currentAssignment.value = null;
          currentAssignment.value_sheet = null;
          currentAssignment.value_type = "literal";
        }
        notifyChange();
        dropdown.classList.add("hidden");
        render();
      });
      dropdown.appendChild(optEl);
    }

    btn.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      dropdown.classList.toggle("hidden");
    });

    // Close on outside click
    const outsideClickHandler = (e) => {
      if (!wrapper.contains(e.target)) {
        dropdown.classList.add("hidden");
      }
    };
    document.addEventListener("mousedown", outsideClickHandler);

    // Store cleanup function
    operatorDropdownCleanup = () => {
      document.removeEventListener("mousedown", outsideClickHandler);
    };

    wrapper.appendChild(btn);
    wrapper.appendChild(dropdown);
    return wrapper;
  }

  function createValueTypeToggle() {
    const toggle = document.createElement("button");
    toggle.type = "button";
    const isRef = currentAssignment.value_type === "variable_ref";
    toggle.className = "value-type-toggle";
    toggle.textContent = isRef ? "{x}" : "123";
    toggle.title = isRef
      ? (t?.switch_to_literal || "Switch to literal value")
      : (t?.switch_to_variable_ref || "Switch to variable reference");

    toggle.addEventListener("click", (e) => {
      e.preventDefault();
      if (currentAssignment.value_type === "variable_ref") {
        currentAssignment.value_type = "literal";
        currentAssignment.value_sheet = null;
      } else {
        currentAssignment.value_type = "variable_ref";
        currentAssignment.value = null;
      }
      notifyChange();
      render();
    });

    return toggle;
  }

  function getVariableType() {
    const v = findVariable(
      variables,
      currentAssignment.sheet,
      currentAssignment.variable,
    );
    return v ? v.block_type : null;
  }

  function notifyChange() {
    if (onChange) onChange({ ...currentAssignment });
  }

  function findVariable(vars, sheetShortcut, variableName) {
    if (!sheetShortcut || !variableName) return null;
    return vars.find(
      (v) =>
        v.sheet_shortcut === sheetShortcut && v.variable_name === variableName,
    );
  }

  // Public API
  return {
    getAssignment: () => ({ ...currentAssignment }),
    focusFirstEmpty: () => {
      for (const key of ["sheet", "variable", "value"]) {
        if (!currentAssignment[key] && comboboxes[key]) {
          comboboxes[key].focus();
          return;
        }
      }
    },
    destroy: () => {
      destroyComboboxes();
      cleanupOperatorDropdown();
      container.innerHTML = "";
    },
  };
}

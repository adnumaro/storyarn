/**
 * Condition builder core — reusable rendering logic for condition UI.
 *
 * Used by both the ConditionBuilder LiveView hook (flow editor) and the
 * Conditional TipTap NodeView (screenplay editor). Accepts a pushEvent
 * callback instead of relying on a LiveView hook directly.
 *
 * Supports both flat format ({logic, rules}) and block format ({logic, blocks}).
 * On init/update, flat conditions are auto-upgraded to block format via
 * ensureBlockFormat(). The flat format is never sent back to the server from
 * this builder — only block format is emitted.
 */

import { createElement, Group, Plus } from "lucide";
import { createConditionBlock } from "../../condition_builder/condition_block";
import { createConditionGroup } from "../../condition_builder/condition_group";
import { OPERATOR_LABELS as DEFAULT_OPERATOR_LABELS } from "../../condition_builder/condition_sentence_templates";
import { createLogicToggle, generateId } from "../../condition_builder/condition_utils";
import { groupVariablesBySheet } from "./utils.js";

const DEFAULT_TRANSLATIONS = {
  operator_labels: DEFAULT_OPERATOR_LABELS,
  match: "Match",
  all: "all",
  any: "any",
  of_the_rules: "of the rules",
  of_the_blocks: "of the blocks",
  switch_mode_info: "Each condition creates an output. First match wins.",
  add_condition: "Add condition",
  add_block: "Add block",
  group: "Group",
  group_selected: "Group selected",
  cancel: "Cancel",
  ungroup: "Ungroup",
  no_conditions: "No conditions set",
  placeholder_sheet: "sheet",
  placeholder_variable: "variable",
  placeholder_operator: "op",
  placeholder_value: "value",
  placeholder_label: "label",
};

/**
 * Auto-upgrades a flat {logic, rules} condition to block format
 * {logic: "all", blocks: [{type: "block", logic, rules}]}.
 * Passes through block-format conditions unchanged.
 */
function ensureBlockFormat(condition) {
  if (!condition) return { logic: "all", blocks: [] };
  if (condition.blocks) return condition;
  // Flat format: wrap rules into a single block
  const rules = condition.rules || [];
  if (rules.length === 0) return { logic: "all", blocks: [] };
  return {
    logic: "all",
    blocks: [
      {
        id: generateId("block"),
        type: "block",
        logic: condition.logic || "all",
        rules: [...rules],
      },
    ],
  };
}

/**
 * Create a condition builder UI inside the given container.
 *
 * @param {Object} opts
 * @param {HTMLElement} opts.container - DOM element to render into
 * @param {Object} opts.condition - Initial condition ({logic, rules} or {logic, blocks})
 * @param {Array} opts.variables - Flat variable list
 * @param {boolean} opts.canEdit - Whether editing is allowed
 * @param {boolean} [opts.switchMode=false] - Switch mode (each block = an output)
 * @param {Object} opts.context - Context map for event payload
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
  let currentCondition = ensureBlockFormat(condition);
  const sheetsWithVariables = groupVariablesBySheet(variables || []);
  let childInstances = [];
  let selectionMode = false;
  const selectedBlockIds = new Set();

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

  function destroyChildren() {
    childInstances.forEach((inst) => {
      inst.destroy?.();
    });
    childInstances = [];
  }

  function render() {
    destroyChildren();
    container.innerHTML = "";

    const blocks = currentCondition.blocks || [];

    // Top-level AND/OR toggle (2+ blocks, not switch mode)
    if (blocks.length >= 2 && !switchMode) {
      const toggle = createLogicToggle({
        logic: currentCondition.logic,
        canEdit,
        ofLabel: t.of_the_blocks,
        translations: t,
        onChange: (newLogic) => {
          currentCondition.logic = newLogic;
          push();
          render();
        },
      });
      toggle.classList.add("mb-2");
      container.appendChild(toggle);
    }

    // Switch mode info
    if (switchMode && blocks.length > 0) {
      const info = document.createElement("p");
      info.className = "text-xs text-base-content/60 mb-2";
      info.textContent = t.switch_mode_info;
      container.appendChild(info);
    }

    // Blocks and groups container
    const blocksContainer = document.createElement("div");
    blocksContainer.className = "space-y-2";
    container.appendChild(blocksContainer);

    blocks.forEach((item, index) => {
      const wrapper = document.createElement("div");
      wrapper.className = "relative";

      // Selection checkbox (for grouping mode)
      if (selectionMode && item.type === "block") {
        const checkWrap = document.createElement("label");
        checkWrap.className = "flex items-start gap-2";

        const checkbox = document.createElement("input");
        checkbox.type = "checkbox";
        checkbox.className = "checkbox checkbox-xs checkbox-primary mt-2";
        checkbox.checked = selectedBlockIds.has(item.id);
        checkbox.addEventListener("change", () => {
          if (checkbox.checked) {
            selectedBlockIds.add(item.id);
          } else {
            selectedBlockIds.delete(item.id);
          }
          updateSelectionUI();
        });
        checkWrap.appendChild(checkbox);

        const contentEl = document.createElement("div");
        contentEl.className = "flex-1";
        checkWrap.appendChild(contentEl);
        wrapper.appendChild(checkWrap);

        renderBlockOrGroup(contentEl, item, index);
      } else {
        renderBlockOrGroup(wrapper, item, index);
      }

      blocksContainer.appendChild(wrapper);
    });

    // Action bar
    if (canEdit) {
      container.appendChild(renderActionBar());
    }

    // Empty state
    if (blocks.length === 0 && !canEdit) {
      const empty = document.createElement("p");
      empty.className = "text-xs text-base-content/50 italic";
      empty.textContent = t.no_conditions;
      container.appendChild(empty);
    }
  }

  function renderBlockOrGroup(containerEl, item, index) {
    if (item.type === "group") {
      const groupInstance = createConditionGroup({
        container: containerEl,
        group: item,
        variables: variables || [],
        sheetsWithVariables,
        canEdit,
        translations: t,
        onChange: (updatedGroup) => {
          currentCondition.blocks[index] = updatedGroup;
          push();
        },
        onUngroup: () => {
          // Dissolve group into standalone blocks
          const innerBlocks = item.blocks || [];
          currentCondition.blocks.splice(index, 1, ...innerBlocks);
          push();
          render();
        },
      });
      childInstances.push(groupInstance);
    } else {
      const blockInstance = createConditionBlock({
        container: containerEl,
        block: item,
        variables: variables || [],
        sheetsWithVariables,
        canEdit,
        switchMode,
        translations: t,
        onChange: (updatedBlock) => {
          currentCondition.blocks[index] = updatedBlock;
          push();
        },
        onRemove: () => {
          currentCondition.blocks.splice(index, 1);
          push();
          render();
        },
      });
      childInstances.push(blockInstance);
    }
  }

  function renderActionBar() {
    const bar = document.createElement("div");
    bar.className = "flex items-center gap-2 mt-2";
    bar.setAttribute("data-role", "action-bar");

    if (selectionMode) {
      // "Group selected (N)" button
      const groupBtn = document.createElement("button");
      groupBtn.type = "button";
      groupBtn.className = "btn btn-primary btn-xs gap-1";
      groupBtn.disabled = selectedBlockIds.size < 2;
      groupBtn.appendChild(createElement(Group, { width: 12, height: 12 }));
      groupBtn.append(` ${t.group_selected} (${selectedBlockIds.size})`);
      groupBtn.addEventListener("click", () => groupSelectedBlocks());
      bar.appendChild(groupBtn);

      // Cancel button
      const cancelBtn = document.createElement("button");
      cancelBtn.type = "button";
      cancelBtn.className = "btn btn-ghost btn-xs";
      cancelBtn.textContent = t.cancel;
      cancelBtn.addEventListener("click", () => {
        selectionMode = false;
        selectedBlockIds.clear();
        render();
      });
      bar.appendChild(cancelBtn);
    } else {
      // Add block button
      const addBtn = document.createElement("button");
      addBtn.type = "button";
      addBtn.className = "btn btn-ghost btn-xs gap-1 border border-dashed border-base-300";
      addBtn.appendChild(createElement(Plus, { width: 12, height: 12 }));
      addBtn.append(` ${t.add_block}`);
      addBtn.addEventListener("click", () => {
        const newBlock = {
          id: generateId("block"),
          type: "block",
          logic: "all",
          rules: [],
        };
        if (switchMode) {
          newBlock.label = "";
        }
        currentCondition.blocks.push(newBlock);
        push();
        render();
      });
      bar.appendChild(addBtn);

      // Group button (only for 2+ standalone blocks, not in switch mode)
      const standAloneBlocks = (currentCondition.blocks || []).filter((b) => b.type === "block");
      if (!switchMode && standAloneBlocks.length >= 2) {
        const groupBtn = document.createElement("button");
        groupBtn.type = "button";
        groupBtn.className = "btn btn-ghost btn-xs gap-1";
        groupBtn.appendChild(createElement(Group, { width: 12, height: 12 }));
        groupBtn.append(` ${t.group}`);
        groupBtn.addEventListener("click", () => {
          selectionMode = true;
          selectedBlockIds.clear();
          render();
        });
        bar.appendChild(groupBtn);
      }
    }

    return bar;
  }

  function updateSelectionUI() {
    // Re-render action bar to update count
    const existingBar = container.querySelector("[data-role='action-bar']");
    if (existingBar) {
      existingBar.remove();
    }
    if (canEdit) {
      container.appendChild(renderActionBar());
    }
  }

  function groupSelectedBlocks() {
    if (selectedBlockIds.size < 2) return;

    const selectedBlocks = [];
    const remainingBlocks = [];

    // Preserve order: collect selected blocks and find insertion point
    let insertIndex = -1;
    currentCondition.blocks.forEach((block, index) => {
      if (block.type === "block" && selectedBlockIds.has(block.id)) {
        selectedBlocks.push(block);
        if (insertIndex === -1) insertIndex = index;
      } else {
        remainingBlocks.push(block);
      }
    });

    if (selectedBlocks.length < 2) return;

    // Create group
    const group = {
      id: generateId("group"),
      type: "group",
      logic: "all",
      blocks: selectedBlocks,
    };

    // Insert group at the position of the first selected block
    remainingBlocks.splice(insertIndex, 0, group);
    currentCondition.blocks = remainingBlocks;

    selectionMode = false;
    selectedBlockIds.clear();
    push();
    render();
  }

  // Initial render
  render();

  return {
    destroy() {
      destroyChildren();
      container.innerHTML = "";
    },
    update(newCondition) {
      currentCondition = ensureBlockFormat(newCondition);
      render();
    },
    getCondition() {
      return currentCondition;
    },
  };
}

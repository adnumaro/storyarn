/**
 * Condition group wrapper component.
 *
 * Renders a group of condition blocks with a group-level AND/OR toggle
 * between the inner blocks. Groups have a colored left border and
 * an "Ungroup" action that dissolves the group into standalone blocks.
 *
 * Groups can only contain blocks (max 1 level of nesting).
 */

import { createElement, Plus, Ungroup } from "lucide";
import { createConditionBlock } from "./condition_block";
import { createLogicToggle, generateId } from "./condition_utils";

/**
 * @param {Object} opts
 * @param {HTMLElement} opts.container - DOM element to render into
 * @param {Object} opts.group - Group data {id, type, logic, blocks}
 * @param {Array} opts.variables - All project variables
 * @param {Array} opts.sheetsWithVariables - Grouped sheets
 * @param {boolean} opts.canEdit - Whether editing is allowed
 * @param {Object} opts.translations - Translated strings
 * @param {Function} opts.onChange - Callback: (updatedGroup) => void
 * @param {Function} opts.onUngroup - Callback: () => void (dissolve group)
 * @returns {{ getGroup: Function, destroy: Function }}
 */
export function createConditionGroup(opts) {
  const {
    container,
    group,
    variables,
    sheetsWithVariables,
    canEdit,
    translations: t,
    onChange,
    onUngroup,
  } = opts;

  let currentGroup = {
    ...group,
    blocks: (group.blocks || []).map((b) => ({ ...b, rules: [...(b.rules || [])] })),
  };
  let blockInstances = [];

  render();

  function render() {
    destroyBlocks();
    container.innerHTML = "";
    container.className =
      "condition-group border-l-4 border-primary/30 pl-3 py-1 rounded-r-lg bg-base-200/30";

    // Header with group-level logic toggle + ungroup button
    const header = document.createElement("div");
    header.className = "flex items-center justify-between mb-2";

    const leftSide = document.createElement("div");
    leftSide.className = "flex items-center gap-2";

    // Group logic toggle
    if (currentGroup.blocks.length >= 2) {
      leftSide.appendChild(
        createLogicToggle({
          logic: currentGroup.logic,
          canEdit,
          ofLabel: t?.of_the_blocks || "of the blocks",
          translations: t,
          onChange: (newLogic) => {
            currentGroup.logic = newLogic;
            notifyChange();
            render();
          },
        }),
      );
    } else {
      const groupLabel = document.createElement("span");
      groupLabel.className = "text-xs text-base-content/60 font-medium";
      groupLabel.textContent = "Group";
      leftSide.appendChild(groupLabel);
    }

    header.appendChild(leftSide);

    // Ungroup button
    if (canEdit) {
      const ungroupBtn = document.createElement("button");
      ungroupBtn.type = "button";
      ungroupBtn.className = "btn btn-ghost btn-xs gap-1 text-base-content/60";
      ungroupBtn.appendChild(createElement(Ungroup, { width: 12, height: 12 }));
      ungroupBtn.append(` ${t?.ungroup || "Ungroup"}`);
      ungroupBtn.addEventListener("click", () => {
        if (onUngroup) onUngroup();
      });
      header.appendChild(ungroupBtn);
    }

    container.appendChild(header);

    // Inner blocks
    const blocksContainer = document.createElement("div");
    blocksContainer.className = "space-y-2";
    container.appendChild(blocksContainer);

    currentGroup.blocks.forEach((block, index) => {
      const blockEl = document.createElement("div");
      blocksContainer.appendChild(blockEl);

      const blockInstance = createConditionBlock({
        container: blockEl,
        block,
        variables,
        sheetsWithVariables,
        canEdit,
        switchMode: false, // Groups are never in switch mode
        translations: t,
        onChange: (updatedBlock) => {
          currentGroup.blocks[index] = updatedBlock;
          notifyChange();
        },
        onRemove: () => {
          currentGroup.blocks.splice(index, 1);
          notifyChange();
          render();
        },
      });

      blockInstances.push(blockInstance);
    });

    // Add block button inside group
    if (canEdit) {
      const addBtn = document.createElement("button");
      addBtn.type = "button";
      addBtn.className =
        "btn btn-ghost btn-xs gap-1 border border-dashed border-base-300 mt-1";
      addBtn.appendChild(createElement(Plus, { width: 12, height: 12 }));
      addBtn.append(` ${t?.add_block || "Add block"}`);
      addBtn.addEventListener("click", () => {
        const newBlock = {
          id: generateId("block"),
          type: "block",
          logic: "all",
          rules: [],
        };
        currentGroup.blocks.push(newBlock);
        notifyChange();
        render();
      });
      container.appendChild(addBtn);
    }
  }

  function destroyBlocks() {
    blockInstances.forEach((b) => b.destroy?.());
    blockInstances = [];
  }

  function notifyChange() {
    if (onChange) onChange({ ...currentGroup, blocks: [...currentGroup.blocks] });
  }

  return {
    getGroup: () => ({ ...currentGroup, blocks: [...currentGroup.blocks] }),
    destroy: () => {
      destroyBlocks();
      container.innerHTML = "";
    },
  };
}

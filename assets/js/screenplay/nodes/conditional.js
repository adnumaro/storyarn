/**
 * Conditional — atom NodeView for condition blocks in the screenplay editor.
 *
 * Renders the full condition builder UI inside a TipTap atom node.
 * Uses the extracted condition_builder_core for rendering logic.
 */

import { Node } from "@tiptap/core";
import { createConditionBuilder } from "../builders/condition_builder_core.js";
import { addExpressionTabs } from "../builders/expression_tab_switcher.js";
import { buildInteractiveHeader } from "../builders/interactive_header.js";
import { BASE_ATTRS } from "./base_attrs.js";

export const Conditional = Node.create({
  name: "conditional",
  group: "screenplayBlock",
  atom: true,
  selectable: true,
  draggable: false,

  addOptions() {
    return {
      liveViewHook: null,
      variables: [],
      canEdit: false,
      translations: {},
    };
  },

  addAttributes() {
    return { ...BASE_ATTRS };
  },

  parseHTML() {
    return [{ tag: 'div[data-node-type="conditional"]' }];
  },

  renderHTML() {
    return [
      "div",
      { "data-node-type": "conditional", class: "sp-conditional" },
      ["div", { class: "sp-interactive-block sp-interactive-condition" }, "Condition"],
    ];
  },

  addNodeView() {
    return ({ node, getPos, editor }) => {
      const hook = this.options.liveViewHook;
      const canEdit = this.options.canEdit;
      const variables = this.options.variables;
      const translations = this.options.translations;

      // Outer wrapper
      const dom = document.createElement("div");
      dom.className = "sp-interactive-block sp-interactive-condition";
      dom.dataset.nodeType = "conditional";
      dom.contentEditable = "false";

      // Header with delete
      const { header } = buildInteractiveHeader("git-branch", "Condition", {
        canEdit,
        onDelete: () => {
          const pos = getPos();
          if (typeof pos === "number") {
            editor
              .chain()
              .focus()
              .deleteRange({ from: pos, to: pos + node.nodeSize })
              .run();
          }
        },
      });
      dom.appendChild(header);

      // Builder container
      const builderContainer = document.createElement("div");
      builderContainer.className = "sp-condition-builder-container condition-builder";
      dom.appendChild(builderContainer);

      const condition = node.attrs.data?.condition || { logic: "all", rules: [] };
      const elementId = node.attrs.elementId;

      const eventName = "update_screenplay_condition";
      const context = { "element-id": String(elementId || "") };

      let builderInstance = null;
      let tabSwitcher = null;
      if (hook) {
        builderInstance = createConditionBuilder({
          container: builderContainer,
          condition,
          variables,
          canEdit,
          context,
          eventName,
          pushEvent: (name, payload) => hook.pushEvent(name, payload),
          translations,
        });

        tabSwitcher = addExpressionTabs({
          dom,
          builderContainer,
          mode: "condition",
          getData: () => builderInstance?.getCondition?.() || condition,
          pushEvent: (name, payload) => hook.pushEvent(name, payload),
          eventName,
          context,
          variables,
          canEdit,
        });
      }

      return {
        dom,
        stopEvent: (event) => dom.contains(event.target) && event.target !== dom,
        update: (updatedNode) => {
          if (updatedNode.type.name !== "conditional") return false;
          node = updatedNode;
          const newCondition = updatedNode.attrs.data?.condition || { logic: "all", rules: [] };
          if (builderInstance) {
            builderInstance.update(newCondition);
          }
          return true;
        },
        destroy: () => {
          tabSwitcher?.destroy();
          if (builderInstance) {
            builderInstance.destroy();
            builderInstance = null;
          }
        },
      };
    };
  },
});

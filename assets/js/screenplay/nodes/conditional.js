/**
 * Conditional — atom NodeView for condition blocks in the screenplay editor.
 *
 * Renders the full condition builder UI inside a TipTap atom node.
 * Uses the extracted condition_builder_core for rendering logic.
 */

import { Node } from "@tiptap/core";
import { BASE_ATTRS } from "./base_attrs.js";
import { buildInteractiveHeader } from "../builders/interactive_header.js";
import { createConditionBuilder } from "../builders/condition_builder_core.js";

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
    const extension = this;

    return ({ node, getPos, editor }) => {
      const hook = extension.options.liveViewHook;
      const canEdit = extension.options.canEdit;
      const variables = extension.options.variables;
      const translations = extension.options.translations;

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
            editor.chain().focus().deleteRange({ from: pos, to: pos + node.nodeSize }).run();
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

      let builderInstance = null;
      if (hook) {
        builderInstance = createConditionBuilder({
          container: builderContainer,
          condition,
          variables,
          canEdit,
          context: { "element-id": String(elementId || "") },
          eventName: "update_screenplay_condition",
          pushEvent: (name, payload) => hook.pushEvent(name, payload),
          translations,
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
          if (builderInstance) {
            builderInstance.destroy();
            builderInstance = null;
          }
        },
      };
    };
  },
});

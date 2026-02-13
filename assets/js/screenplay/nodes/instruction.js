/**
 * Instruction — atom NodeView for instruction/assignment blocks in the screenplay editor.
 *
 * Renders the full instruction builder UI inside a TipTap atom node.
 * Uses the extracted instruction_builder_core for rendering logic.
 */

import { Node } from "@tiptap/core";
import { BASE_ATTRS } from "./base_attrs.js";
import { buildInteractiveHeader } from "../builders/interactive_header.js";
import { createInstructionBuilder } from "../builders/instruction_builder_core.js";

export const Instruction = Node.create({
  name: "instruction",
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
    return [{ tag: 'div[data-node-type="instruction"]' }];
  },

  renderHTML() {
    return [
      "div",
      { "data-node-type": "instruction", class: "sp-instruction" },
      ["div", { class: "sp-interactive-block sp-interactive-instruction" }, "Instruction"],
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
      dom.className = "sp-interactive-block sp-interactive-instruction";
      dom.dataset.nodeType = "instruction";
      dom.contentEditable = "false";

      // Header with delete
      const { header } = buildInteractiveHeader("zap", "Instruction", {
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
      builderContainer.className = "sp-instruction-builder-container";
      dom.appendChild(builderContainer);

      const assignments = node.attrs.data?.assignments || [];
      const elementId = node.attrs.elementId;

      let builderInstance = null;
      if (hook) {
        builderInstance = createInstructionBuilder({
          container: builderContainer,
          assignments,
          variables,
          canEdit,
          context: { "element-id": String(elementId || "") },
          eventName: "update_screenplay_instruction",
          pushEvent: (name, payload) => hook.pushEvent(name, payload),
          translations,
        });
      }

      return {
        dom,
        stopEvent: (event) => dom.contains(event.target) && event.target !== dom,
        update: (updatedNode) => {
          if (updatedNode.type.name !== "instruction") return false;
          node = updatedNode;
          const newAssignments = updatedNode.attrs.data?.assignments || [];
          if (builderInstance) {
            builderInstance.update(newAssignments);
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

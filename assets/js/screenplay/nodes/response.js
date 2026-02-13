/**
 * Response — atom NodeView for response/choice blocks in the screenplay editor.
 *
 * Renders the full choice list with text inputs, per-choice condition/instruction
 * builders, and linked page controls.
 */

import { Node } from "@tiptap/core";
import { createElement, CheckCircle, AlertCircle, Files } from "lucide";
import { BASE_ATTRS } from "./base_attrs.js";
import { buildInteractiveHeader } from "../builders/interactive_header.js";
import { createResponseBuilder } from "../builders/response_builder.js";

export const Response = Node.create({
  name: "response",
  group: "screenplayBlock",
  atom: true,
  selectable: true,
  draggable: false,

  addOptions() {
    return {
      liveViewHook: null,
      variables: [],
      canEdit: false,
      linkedPages: {},
      translations: {},
    };
  },

  addAttributes() {
    return { ...BASE_ATTRS };
  },

  parseHTML() {
    return [{ tag: 'div[data-node-type="response"]' }];
  },

  renderHTML() {
    return [
      "div",
      { "data-node-type": "response", class: "sp-response" },
      ["div", { class: "sp-interactive-block sp-interactive-response" }, "Responses"],
    ];
  },

  addNodeView() {
    const extension = this;

    return ({ node, getPos, editor }) => {
      const hook = extension.options.liveViewHook;
      const canEdit = extension.options.canEdit;
      const variables = extension.options.variables;
      const translations = extension.options.translations;
      let linkedPages = extension.options.linkedPages || {};

      // Outer wrapper
      const dom = document.createElement("div");
      dom.className = "sp-interactive-block sp-interactive-response";
      dom.dataset.nodeType = "response";
      dom.contentEditable = "false";

      // Header with actions + delete
      const { header, actionsSlot } = buildInteractiveHeader("list", "Responses", {
        canEdit,
        onDelete: () => {
          const pos = getPos();
          if (typeof pos === "number") {
            editor.chain().focus().deleteRange({ from: pos, to: pos + node.nodeSize }).run();
          }
        },
      });

      // Status icons + generate button in header actions
      updateHeaderActions(actionsSlot, node, canEdit, linkedPages, hook);
      dom.appendChild(header);

      // Builder container
      const builderContainer = document.createElement("div");
      builderContainer.className = "sp-response-builder-container";
      dom.appendChild(builderContainer);

      const elementId = String(node.attrs.elementId || "");

      let builderInstance = null;
      if (hook) {
        builderInstance = createResponseBuilder({
          container: builderContainer,
          data: node.attrs.data || {},
          variables,
          canEdit,
          linkedPages,
          pushEvent: (name, payload) => hook.pushEvent(name, payload),
          elementId,
          translations,
        });
      }

      return {
        dom,
        stopEvent: (event) => dom.contains(event.target) && event.target !== dom,
        update: (updatedNode) => {
          if (updatedNode.type.name !== "response") return false;
          node = updatedNode;

          // Update linked pages from hook if available
          if (hook && hook._linkedPages) {
            linkedPages = hook._linkedPages;
          }

          updateHeaderActions(actionsSlot, updatedNode, canEdit, linkedPages, hook);

          if (builderInstance) {
            builderInstance.update(updatedNode.attrs.data || {});
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

/**
 * Update the header actions slot with status icons and generate button.
 */
function updateHeaderActions(actionsSlot, node, canEdit, linkedPages, hook) {
  actionsSlot.innerHTML = "";

  const choices = node.attrs.data?.choices || [];
  const total = choices.length;
  const linkedCount = choices.filter((c) => c.linked_screenplay_id).length;
  const allLinked = linkedCount > 0 && linkedCount === total;
  const someUnlinked = linkedCount > 0 && linkedCount < total;
  const hasUnlinked = total > 0 && linkedCount < total;
  const elementId = String(node.attrs.elementId || "");

  if (allLinked) {
    const icon = createElement(CheckCircle, { width: 14, height: 14 });
    icon.classList.add("text-success");
    actionsSlot.appendChild(icon);
  }

  if (someUnlinked) {
    const icon = createElement(AlertCircle, { width: 14, height: 14 });
    icon.classList.add("text-warning");
    actionsSlot.appendChild(icon);
  }

  if (canEdit && hasUnlinked && hook) {
    const genBtn = document.createElement("button");
    genBtn.type = "button";
    genBtn.className = "sp-generate-pages-btn";
    genBtn.title = "Create pages for all unlinked choices";

    const filesIcon = createElement(Files, { width: 12, height: 12 });
    genBtn.appendChild(filesIcon);
    genBtn.append(" Generate pages");

    genBtn.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      hook.pushEvent("generate_all_linked_pages", { "element-id": elementId });
    });
    actionsSlot.appendChild(genBtn);
  }
}

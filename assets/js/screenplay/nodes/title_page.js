/**
 * TitlePage — atom NodeView for title page metadata in the screenplay editor.
 *
 * Renders an interactive form with editable fields (title, credit, author, etc.)
 * Uses the extracted title_page_builder for rendering logic.
 */

import { Node } from "@tiptap/core";
import { BASE_ATTRS } from "./base_attrs.js";
import { buildInteractiveHeader } from "../builders/interactive_header.js";
import { createTitlePageBuilder } from "../builders/title_page_builder.js";

export const TitlePage = Node.create({
  name: "titlePage",
  group: "screenplayBlock",
  atom: true,
  selectable: true,
  draggable: false,

  addOptions() {
    return {
      liveViewHook: null,
      canEdit: false,
    };
  },

  addAttributes() {
    return { ...BASE_ATTRS };
  },

  parseHTML() {
    return [{ tag: 'div[data-node-type="title_page"]' }];
  },

  renderHTML() {
    return [
      "div",
      { "data-node-type": "title_page", class: "sp-title_page" },
      ["div", { class: "sp-interactive-block sp-interactive-title-page" }, "Title Page"],
    ];
  },

  addNodeView() {
    const extension = this;

    return ({ node, getPos, editor }) => {
      const hook = extension.options.liveViewHook;
      const canEdit = extension.options.canEdit;

      // Outer wrapper
      const dom = document.createElement("div");
      dom.className = "sp-interactive-block sp-interactive-title-page";
      dom.dataset.nodeType = "title_page";
      dom.contentEditable = "false";

      // Header with delete
      const { header } = buildInteractiveHeader("file-text", "Title Page", {
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
      builderContainer.className = "sp-title-page-builder-container";
      dom.appendChild(builderContainer);

      const data = node.attrs.data || {};
      const elementId = node.attrs.elementId;

      let builderInstance = null;
      if (hook) {
        builderInstance = createTitlePageBuilder({
          container: builderContainer,
          data,
          canEdit,
          context: { "element-id": String(elementId || "") },
          eventName: "update_title_page",
          pushEvent: (name, payload) => hook.pushEvent(name, payload),
        });
      }

      return {
        dom,
        update: (updatedNode) => {
          if (updatedNode.type.name !== "titlePage") return false;
          node = updatedNode;
          const newData = updatedNode.attrs.data || {};
          if (builderInstance) {
            builderInstance.update(newData);
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

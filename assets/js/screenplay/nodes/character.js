/**
 * Character — screenplay character name node with optional sheet reference.
 *
 * When `sheetId` is set (via # mention in a CHARACTER block), the character
 * name gets a visual reference style. Cmd/Ctrl+Click navigates to the sheet
 * (handled by the ScreenplayEditor hook, same as inline mentions).
 */

import { Node, mergeAttributes } from "@tiptap/core";
import { BASE_ATTRS } from "./base_attrs.js";

export const Character = Node.create({
  name: "character",
  group: "screenplayBlock",
  content: "inline*",
  defining: true,

  addOptions() {
    return {
      /** LiveView hook instance for pushing events to the server. */
      liveViewHook: null,
    };
  },

  addAttributes() {
    return {
      ...BASE_ATTRS,
      sheetId: {
        default: null,
        parseHTML: (el) => el.dataset.sheetId || null,
        renderHTML: (attrs) => {
          if (!attrs.sheetId) return {};
          return { "data-sheet-id": attrs.sheetId };
        },
      },
    };
  },

  parseHTML() {
    return [{ tag: 'div[data-node-type="character"]' }];
  },

  renderHTML({ HTMLAttributes }) {
    return [
      "div",
      mergeAttributes(HTMLAttributes, {
        "data-node-type": "character",
        class: "sp-character",
      }),
      0,
    ];
  },

  addNodeView() {
    const extension = this;

    return ({ node, getPos, editor }) => {
      const hook = extension.options.liveViewHook;

      const dom = document.createElement("div");
      dom.classList.add("sp-character");
      dom.dataset.nodeType = "character";

      // Editable content area managed by ProseMirror
      const contentDOM = document.createElement("span");
      contentDOM.classList.add("sp-character-content");
      dom.appendChild(contentDOM);

      let currentSheetId = node.attrs.sheetId;
      let currentNode = node;

      function updateState(sheetId) {
        if (sheetId) {
          dom.classList.add("sp-character-ref");
          dom.dataset.sheetId = sheetId;
        } else {
          dom.classList.remove("sp-character-ref");
          delete dom.dataset.sheetId;
        }
      }

      updateState(currentSheetId);

      return {
        dom,
        contentDOM,
        update: (updatedNode) => {
          if (updatedNode.type.name !== "character") return false;
          currentNode = updatedNode;
          currentSheetId = updatedNode.attrs.sheetId;

          // Auto-clear reference when content is deleted
          if (currentSheetId && updatedNode.content.size === 0) {
            const pos = getPos();
            if (typeof pos === "number") {
              editor.view.dispatch(
                editor.state.tr.setNodeMarkup(pos, undefined, {
                  ...updatedNode.attrs,
                  sheetId: null,
                }),
              );
              const elementId = updatedNode.attrs.elementId;
              if (elementId && hook) {
                hook.pushEvent("clear_character_sheet", {
                  id: String(elementId),
                });
              }
              return true;
            }
          }

          updateState(currentSheetId);
          return true;
        },
      };
    };
  },
});

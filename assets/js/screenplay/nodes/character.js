/**
 * Character — screenplay character name node with optional sheet reference.
 *
 * When `sheetId` is set (via # mention in a CHARACTER block), a NodeView
 * renders action buttons (navigate to sheet, clear reference) alongside
 * the character name. The text is always editable via ProseMirror's contentDOM.
 */

import { Node, mergeAttributes } from "@tiptap/core";
import { createElement, ExternalLink, X } from "lucide";
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

      // Outer wrapper
      const dom = document.createElement("div");
      dom.classList.add("sp-character");
      dom.dataset.nodeType = "character";

      // Editable content area managed by ProseMirror
      const contentDOM = document.createElement("span");
      contentDOM.classList.add("sp-character-content");
      dom.appendChild(contentDOM);

      // Action buttons container (nav + clear)
      const actions = document.createElement("span");
      actions.classList.add("sp-character-actions");
      actions.contentEditable = "false";

      const navBtn = document.createElement("button");
      navBtn.type = "button";
      navBtn.className = "sp-character-nav";
      navBtn.title = "Go to sheet";
      navBtn.appendChild(
        createElement(ExternalLink, { width: 12, height: 12 }),
      );
      navBtn.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        if (currentSheetId && hook) {
          hook.pushEvent("navigate_to_sheet", { sheet_id: currentSheetId });
        }
      });
      actions.appendChild(navBtn);

      const clearBtn = document.createElement("button");
      clearBtn.type = "button";
      clearBtn.className = "sp-character-clear";
      clearBtn.title = "Remove reference";
      clearBtn.appendChild(createElement(X, { width: 12, height: 12 }));
      clearBtn.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        const pos = getPos();
        if (typeof pos !== "number") return;

        // Clear sheetId in TipTap and empty the content
        editor
          .chain()
          .focus()
          .command(({ tr, dispatch }) => {
            if (dispatch) {
              tr.setNodeMarkup(pos, undefined, {
                ...currentNode.attrs,
                sheetId: null,
              });
              // Clear inline content
              const start = pos + 1;
              const end = pos + 1 + currentNode.content.size;
              if (end > start) {
                tr.delete(start, end);
              }
            }
            return true;
          })
          .run();

        // Persist immediately to server
        const elementId = currentNode.attrs.elementId;
        if (elementId && hook) {
          hook.pushEvent("clear_character_sheet", { id: String(elementId) });
        }
      });
      actions.appendChild(clearBtn);

      dom.appendChild(actions);

      // Track current state for event handlers
      let currentSheetId = node.attrs.sheetId;
      let currentNode = node;

      function updateState(sheetId) {
        if (sheetId) {
          dom.classList.add("sp-character-ref");
          dom.dataset.sheetId = sheetId;
          actions.style.display = "";
        } else {
          dom.classList.remove("sp-character-ref");
          delete dom.dataset.sheetId;
          actions.style.display = "none";
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
          updateState(currentSheetId);
          return true;
        },
      };
    };
  },
});

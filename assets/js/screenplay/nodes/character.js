/**
 * Character — screenplay character name node with optional sheet reference.
 *
 * When `sheetId` is set (via # mention in a CHARACTER block), the character
 * name gets a visual reference style. Cmd/Ctrl+Click navigates to the sheet
 * (handled by the ScreenplayEditor hook, same as inline mentions).
 *
 * NO custom NodeView — ProseMirror fully manages the DOM via renderHTML.
 * The nested <span class="sp-character-content"> provides a CSS target for
 * the badge styling when a sheet reference is active.
 *
 * Auto-clear: when the user deletes all text from a referenced character,
 * an appendTransaction plugin automatically clears the sheetId.
 */

import { Node, mergeAttributes } from "@tiptap/core";
import { Plugin } from "prosemirror-state";
import { BASE_ATTRS } from "./base_attrs.js";

export const Character = Node.create({
  name: "character",
  group: "screenplayBlock",
  content: "inline*",
  defining: true,

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
    return [
      {
        tag: 'div[data-node-type="character"]',
        // When pasting HTML with the nested span, read content from it;
        // otherwise fall back to the matched div itself.
        contentElement: (node) =>
          node.querySelector(".sp-character-content") || node,
      },
    ];
  },

  renderHTML({ HTMLAttributes }) {
    const hasRef = !!HTMLAttributes["data-sheet-id"];
    return [
      "div",
      mergeAttributes(HTMLAttributes, {
        "data-node-type": "character",
        class: hasRef ? "sp-character sp-character-ref" : "sp-character",
      }),
      ["span", { class: "sp-character-content" }, 0],
    ];
  },

  addProseMirrorPlugins() {
    return [
      new Plugin({
        appendTransaction(_transactions, _oldState, newState) {
          let tr = null;

          newState.doc.forEach((node, pos) => {
            if (
              node.type.name === "character" &&
              node.attrs.sheetId &&
              node.content.size === 0
            ) {
              if (!tr) tr = newState.tr;
              tr.setNodeMarkup(pos, undefined, {
                ...node.attrs,
                sheetId: null,
              });
            }
          });

          return tr;
        },
      }),
    ];
  },
});

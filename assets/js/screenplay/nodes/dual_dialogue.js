/**
 * DualDialogue — atom NodeView for side-by-side dialogue blocks.
 *
 * Renders a two-column layout with character name, optional parenthetical,
 * and dialogue textarea for each side. Blur events push updates to server,
 * click events toggle parenthetical visibility.
 */

import { Node } from "@tiptap/core";
import { createElement, Minus, Plus, Trash2 } from "lucide";
import { BASE_ATTRS } from "./base_attrs.js";

export const DualDialogue = Node.create({
  name: "dualDialogue",
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
    return [{ tag: 'div[data-node-type="dualDialogue"]' }];
  },

  renderHTML() {
    return [
      "div",
      { "data-node-type": "dualDialogue", class: "sp-dual-dialogue-wrapper" },
      ["div", { class: "sp-dual-dialogue" }, "Dual Dialogue"],
    ];
  },

  addNodeView() {
    return ({ node, getPos, editor }) => {
      const hook = this.options.liveViewHook;
      const canEdit = this.options.canEdit;

      const dom = document.createElement("div");
      dom.className = "sp-dual-dialogue-wrapper";
      dom.dataset.nodeType = "dualDialogue";
      dom.contentEditable = "false";

      // Delete button
      if (canEdit) {
        const deleteBtn = document.createElement("button");
        deleteBtn.type = "button";
        deleteBtn.className = "sp-interactive-delete sp-dual-delete";
        deleteBtn.title = "Delete block";
        deleteBtn.appendChild(createElement(Trash2, { width: 14, height: 14 }));
        deleteBtn.addEventListener("click", () => {
          const pos = getPos();
          if (typeof pos === "number") {
            editor
              .chain()
              .focus()
              .deleteRange({ from: pos, to: pos + node.nodeSize })
              .run();
          }
        });
        dom.appendChild(deleteBtn);
      }

      // Two-column grid
      const grid = document.createElement("div");
      grid.className = "sp-dual-dialogue";
      dom.appendChild(grid);

      const elementId = String(node.attrs.elementId || "");

      function buildColumn(side, sideData) {
        const col = document.createElement("div");
        col.className = "sp-dual-column";

        // Character
        const charWrap = document.createElement("div");
        charWrap.className = "sp-dual-character";
        if (canEdit) {
          const charInput = document.createElement("input");
          charInput.type = "text";
          charInput.value = sideData.character || "";
          charInput.placeholder = "CHARACTER";
          charInput.className = "sp-dual-character-input";
          charInput.addEventListener("blur", () => {
            if (hook) {
              hook.pushEvent("update_dual_dialogue", {
                "element-id": elementId,
                side,
                field: "character",
                value: charInput.value,
              });
            }
          });
          charWrap.appendChild(charInput);
        } else {
          const charText = document.createElement("span");
          charText.className = "sp-dual-character-text";
          charText.textContent = sideData.character || "";
          charWrap.appendChild(charText);
        }
        col.appendChild(charWrap);

        // Parenthetical (only if enabled)
        if (sideData.parenthetical != null) {
          const parenWrap = document.createElement("div");
          parenWrap.className = "sp-dual-parenthetical";
          if (canEdit) {
            const parenInput = document.createElement("input");
            parenInput.type = "text";
            parenInput.value = sideData.parenthetical || "";
            parenInput.placeholder = "(direction)";
            parenInput.className = "sp-dual-paren-input";
            parenInput.addEventListener("blur", () => {
              if (hook) {
                hook.pushEvent("update_dual_dialogue", {
                  "element-id": elementId,
                  side,
                  field: "parenthetical",
                  value: parenInput.value,
                });
              }
            });
            parenWrap.appendChild(parenInput);
          } else {
            const parenText = document.createElement("span");
            parenText.className = "sp-dual-paren-text";
            parenText.textContent = sideData.parenthetical || "";
            parenWrap.appendChild(parenText);
          }
          col.appendChild(parenWrap);
        }

        // Parenthetical toggle button
        if (canEdit) {
          const toggleBtn = document.createElement("button");
          toggleBtn.type = "button";
          toggleBtn.className = `sp-dual-toggle-paren${sideData.parenthetical != null ? " sp-dual-toggle-paren-active" : ""}`;
          toggleBtn.title = "Toggle parenthetical";
          const toggleIcon = sideData.parenthetical != null ? Minus : Plus;
          toggleBtn.appendChild(createElement(toggleIcon, { width: 12, height: 12 }));
          toggleBtn.addEventListener("click", () => {
            if (hook) {
              hook.pushEvent("toggle_dual_parenthetical", {
                "element-id": elementId,
                side,
              });
            }
          });
          col.appendChild(toggleBtn);
        }

        // Dialogue
        const dialWrap = document.createElement("div");
        dialWrap.className = "sp-dual-dialogue-text";
        if (canEdit) {
          const textarea = document.createElement("textarea");
          textarea.placeholder = "Dialogue...";
          textarea.className = "sp-dual-dialogue-input";
          textarea.value = sideData.dialogue || "";
          textarea.addEventListener("blur", () => {
            if (hook) {
              hook.pushEvent("update_dual_dialogue", {
                "element-id": elementId,
                side,
                field: "dialogue",
                value: textarea.value,
              });
            }
          });
          dialWrap.appendChild(textarea);
        } else {
          const dialText = document.createElement("span");
          dialText.className = "sp-dual-dialogue-readonly";
          dialText.textContent = sideData.dialogue || "";
          dialWrap.appendChild(dialText);
        }
        col.appendChild(dialWrap);

        return col;
      }

      function renderColumns() {
        grid.innerHTML = "";
        const data = node.attrs.data || {};
        grid.appendChild(buildColumn("left", data.left || {}));
        grid.appendChild(buildColumn("right", data.right || {}));
      }

      renderColumns();

      return {
        dom,
        stopEvent: (event) => dom.contains(event.target) && event.target !== dom,
        update: (updatedNode) => {
          if (updatedNode.type.name !== "dualDialogue") return false;
          node = updatedNode;
          renderColumns();
          return true;
        },
        destroy: () => {},
      };
    };
  },
});

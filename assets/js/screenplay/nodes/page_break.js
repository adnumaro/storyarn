/**
 * PageBreak — atom node (no editable content).
 *
 * Rendered as a horizontal rule-like visual separator.
 * Selectable and deletable via Backspace/Delete.
 */

import { Node } from "@tiptap/core";
import { BASE_ATTRS } from "./base_attrs.js";

export const PageBreak = Node.create({
  name: "pageBreak",
  group: "screenplayBlock",
  atom: true,
  selectable: true,
  draggable: false,

  addAttributes() {
    return { ...BASE_ATTRS };
  },

  parseHTML() {
    return [{ tag: 'div[data-node-type="page_break"]' }];
  },

  renderHTML() {
    return [
      "div",
      { "data-node-type": "page_break", class: "sp-page_break" },
      ["div", { class: "sp-page-break-line" }],
    ];
  },
});

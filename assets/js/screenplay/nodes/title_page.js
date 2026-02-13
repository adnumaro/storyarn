/**
 * TitlePage — atom node for title page markers.
 *
 * Renders as a simple badge. Selectable and deletable via Backspace/Delete.
 */

import { Node } from "@tiptap/core";
import { BASE_ATTRS } from "./base_attrs.js";

export const TitlePage = Node.create({
  name: "titlePage",
  group: "screenplayBlock",
  atom: true,
  selectable: true,
  draggable: false,

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
      ["div", { class: "sp-stub" }, ["span", { class: "sp-stub-badge" }, "Title Page"]],
    ];
  },
});

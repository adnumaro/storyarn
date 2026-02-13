/**
 * JumpMarker — atom node for flow jump markers.
 *
 * Renders as a simple badge. Selectable and deletable via Backspace/Delete.
 */

import { Node } from "@tiptap/core";
import { BASE_ATTRS } from "./base_attrs.js";

export const JumpMarker = Node.create({
  name: "jumpMarker",
  group: "screenplayBlock",
  atom: true,
  selectable: true,
  draggable: false,

  addAttributes() {
    return { ...BASE_ATTRS };
  },

  parseHTML() {
    return [{ tag: 'div[data-node-type="jump_marker"]' }];
  },

  renderHTML() {
    return [
      "div",
      { "data-node-type": "jump_marker", class: "sp-jump_marker" },
      ["div", { class: "sp-stub" }, ["span", { class: "sp-stub-badge" }, "Jump Marker"]],
    ];
  },
});

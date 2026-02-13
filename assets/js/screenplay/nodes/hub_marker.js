/**
 * HubMarker — atom node for flow hub markers.
 *
 * Renders as a simple badge. Selectable and deletable via Backspace/Delete.
 */

import { Node } from "@tiptap/core";
import { BASE_ATTRS } from "./base_attrs.js";

export const HubMarker = Node.create({
  name: "hubMarker",
  group: "screenplayBlock",
  atom: true,
  selectable: true,
  draggable: false,

  addAttributes() {
    return { ...BASE_ATTRS };
  },

  parseHTML() {
    return [{ tag: 'div[data-node-type="hub_marker"]' }];
  },

  renderHTML() {
    return [
      "div",
      { "data-node-type": "hub_marker", class: "sp-hub_marker" },
      ["div", { class: "sp-stub" }, ["span", { class: "sp-stub-badge" }, "Hub Marker"]],
    ];
  },
});

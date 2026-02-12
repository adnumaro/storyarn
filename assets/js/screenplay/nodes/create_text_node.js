/**
 * Factory for screenplay text block nodes.
 *
 * All text nodes share the same structure: they belong to the "screenplayBlock"
 * group, accept inline content, and carry `elementId` + `data` attributes for
 * server sync. They differ only in name, server type, and CSS class.
 */

import { Node, mergeAttributes } from "@tiptap/core";
import { BASE_ATTRS } from "./base_attrs.js";

/**
 * Creates a screenplay text block node extension.
 *
 * @param {string} name - TipTap node name (camelCase, e.g. "sceneHeading")
 * @param {string} serverType - Server element type (snake_case, e.g. "scene_heading")
 * @returns {Node} TipTap node extension
 */
export function createTextNode(name, serverType) {
  return Node.create({
    name,
    group: "screenplayBlock",
    content: "inline*",
    defining: true,

    addAttributes() {
      return { ...BASE_ATTRS };
    },

    parseHTML() {
      return [{ tag: `div[data-node-type="${serverType}"]` }];
    },

    renderHTML({ HTMLAttributes }) {
      return [
        "div",
        mergeAttributes(HTMLAttributes, {
          "data-node-type": serverType,
          class: `sp-${serverType}`,
        }),
        0,
      ];
    },
  });
}

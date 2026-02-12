/**
 * ScreenplayDoc — custom top-level document node.
 *
 * Restricts the document to only contain screenplay block nodes.
 * Replaces the default Document node from StarterKit.
 */

import { Node } from "@tiptap/core";

export const ScreenplayDoc = Node.create({
  name: "doc",
  topNode: true,
  content: "screenplayBlock+",
});

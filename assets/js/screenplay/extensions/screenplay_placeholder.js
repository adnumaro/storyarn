/**
 * ScreenplayPlaceholder — configures @tiptap/extension-placeholder
 * with per-node-type placeholder text.
 *
 * Only the currently focused empty block shows its placeholder.
 */

import Placeholder from "@tiptap/extension-placeholder";

const PLACEHOLDERS = {
  sceneHeading: "INT. LOCATION - TIME",
  action: "Describe the action...",
  character: "CHARACTER NAME",
  dialogue: "Dialogue text...",
  parenthetical: "(acting direction)",
  transition: "CUT TO:",
  note: "Note...",
  section: "Section heading",
};

export const ScreenplayPlaceholder = Placeholder.configure({
  showOnlyCurrent: true,
  includeChildren: false,
  placeholder: ({ node }) => PLACEHOLDERS[node.type.name] || "",
});

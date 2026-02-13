/**
 * TransitionAlignPlugin — TipTap extension that toggles left-alignment on
 * transition blocks whose content ends with "IN:" (e.g. "FADE IN:").
 *
 * Mirrors the server-side left_transition? logic in element_renderer.ex
 * so the edit-mode editor matches read-mode rendering.
 *
 * Uses ProseMirror node decorations to add/remove the `.sp-transition-left`
 * CSS class without modifying the node itself.
 */

import { Decoration, DecorationSet } from "@tiptap/pm/view";
import { createDecorationPlugin } from "./create_decoration_plugin.js";

/**
 * Check if a transition's text content should be left-aligned.
 * Matches element_renderer.ex: content |> trim |> upcase |> ends_with?("IN:")
 */
function isLeftTransition(textContent) {
  return textContent.trim().toUpperCase().endsWith("IN:");
}

/**
 * Compute node decorations for transition blocks that need left-alignment.
 */
function computeTransitionDecorations(doc) {
  const decorations = [];

  doc.forEach((node, pos) => {
    if (node.type.name !== "transition") return;

    const text = node.textContent || "";
    if (isLeftTransition(text)) {
      decorations.push(
        Decoration.node(pos, pos + node.nodeSize, {
          class: "sp-transition-left",
        }),
      );
    }
  });

  return DecorationSet.create(doc, decorations);
}

export const TransitionAlignPlugin = createDecorationPlugin(
  "transitionAlignPlugin",
  computeTransitionDecorations,
);

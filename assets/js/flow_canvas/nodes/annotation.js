/**
 * Annotation node definition.
 *
 * Free-floating sticky note with no input/output pins.
 * Supports inline text editing on double-click.
 */

import { html } from "lit";
import { StickyNote } from "lucide";
import { createIconSvg } from "../node_config.js";

const ICON = createIconSvg(StickyNote);

export default {
  config: {
    label: "Note",
    color: "#fbbf24",
    icon: ICON,
    inputs: [],
    outputs: [],
  },

  needsRebuild(prev, next) {
    return (
      prev.text !== next.text || prev.color !== next.color || prev.font_size !== next.font_size
    );
  },

  render({ nodeData, selected }) {
    const color = nodeData.color || "#fbbf24";
    const sizeClass = `annotation-${nodeData.font_size || "md"}`;
    const text = nodeData.text || "";

    return html`
      <div
        class="annotation-wrapper ${sizeClass} ${selected ? "selected" : ""}"
        style="--ann-color: ${color}"
      >
        <div class="annotation-bg"></div>
        <div class="annotation-text">${text || "…"}</div>
        <div class="annotation-fold"></div>
      </div>
    `;
  },

  renderEdit({ nodeData, onSave }) {
    const color = nodeData.color || "#fbbf24";
    const sizeClass = `annotation-${nodeData.font_size || "md"}`;

    return html`
      <div
        class="annotation-wrapper ${sizeClass}"
        style="--ann-color: ${color}"
      >
        <div class="annotation-bg"></div>
        <textarea
          class="annotation-text annotation-edit-textarea"
          .value=${nodeData.text || ""}
          @blur=${(e) => onSave("text", e.target.value)}
          @keydown=${(e) => {
            if (e.key === "Escape") e.target.blur();
          }}
          placeholder="…"
          autofocus
        ></textarea>
        <div class="annotation-fold"></div>
      </div>
    `;
  },
};

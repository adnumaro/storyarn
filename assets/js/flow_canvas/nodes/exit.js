/**
 * Exit node type definition.
 */
import { html } from "lit";
import { Square } from "lucide";
import { createIconSvg } from "../node_config.js";
import { nodeShell, defaultHeader, renderPreview, renderSockets } from "./render_helpers.js";

export default {
  config: {
    label: "Exit",
    color: "#ef4444",
    icon: createIconSvg(Square),
    inputs: ["input"],
    outputs: [],
  },

  render(ctx) {
    const { node, nodeData, config, selected, emit } = ctx;
    const color = this.nodeColor(nodeData, config);
    const preview = this.getPreviewText(nodeData);
    return nodeShell(color, selected, html`
      ${defaultHeader(config, color, [])}
      ${renderPreview(preview)}
      <div class="content">${renderSockets(node, nodeData, this, emit)}</div>
    `);
  },

  getPreviewText(data) {
    const label = data.label || "";
    const icon = data.is_success === false ? "✕" : "✓";
    return label ? `${icon} ${label}` : icon;
  },

  nodeColor(data, config) {
    if (data.is_success === false) return "#ef4444";
    if (data.is_success !== false) return "#22c55e";
    return config.color;
  },

  needsRebuild(_oldData, _newData) {
    return false;
  },
};

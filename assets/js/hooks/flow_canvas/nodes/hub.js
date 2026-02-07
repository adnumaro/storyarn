/**
 * Hub node type definition.
 */
import { html } from "lit";
import { LogIn } from "lucide";
import { createIconSvg } from "../node_config.js";
import { nodeShell, defaultHeader, renderNavLink, renderSockets } from "./render_helpers.js";

export default {
  config: {
    label: "Hub",
    color: "#8b5cf6",
    icon: createIconSvg(LogIn),
    inputs: ["input"],
    outputs: ["output"],
  },

  render(ctx) {
    const { node, nodeData, config, selected, emit, hubsMap } = ctx;
    const color = this.nodeColor(nodeData, config);
    const hubEntry = hubsMap?.[nodeData.hub_id];
    const navText = `↗ ${hubEntry?.jumpCount || 0} jumps`;

    return nodeShell(color, selected, html`
      ${defaultHeader(config, color, [])}
      ${renderNavLink(navText, "navigate-to-jumps", "hubDbId", node.nodeId, emit)}
      <div class="content">${renderSockets(node, nodeData, this, emit)}</div>
    `);
  },

  getPreviewText(data) {
    const label = data.label || "";
    const hubId = data.hub_id || "";
    if (label && hubId) return `${label} (${hubId})`;
    return label || hubId;
  },

  nodeColor(data, config) {
    return data.color_hex || config.color;
  },

  needsRebuild(_oldData, _newData) {
    return false;
  },
};

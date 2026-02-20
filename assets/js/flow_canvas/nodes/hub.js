/**
 * Hub node type definition.
 */
import { html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { ArrowUpRight, LogIn } from "lucide";
import { createIconHTML, createIconSvg } from "../node_config.js";
import { defaultHeader, nodeShell, renderNavLink, renderSockets } from "./render_helpers.js";

// Pre-create jump count icon
const JUMP_ICON = createIconHTML(ArrowUpRight, { size: 12 });

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
    const jumpCount = hubEntry?.jumpCount || 0;
    const navContent = html`<span style="display:inline-flex;align-items:center;gap:4px">${unsafeSVG(JUMP_ICON)} ${jumpCount} jumps</span>`;

    return nodeShell(
      color,
      selected,
      html`
      ${defaultHeader(config, color, [])}
      ${renderNavLink(navContent, "navigate-to-jumps", "hubDbId", node.nodeId, emit)}
      <div class="content">${renderSockets(node, nodeData, this, emit)}</div>
    `,
    );
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

  needsRebuild(oldData, newData) {
    if (oldData?.color_hex !== newData.color_hex) return true;
    return false;
  },
};

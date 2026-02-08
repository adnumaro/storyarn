/**
 * Entry node type definition.
 */
import { html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { Play, Box, Square } from "lucide";
import { createIconSvg, createIconHTML } from "../node_config.js";
import { nodeShell, defaultHeader, renderNavLink, renderSockets } from "./render_helpers.js";

// Pre-create reference icons
const SUBFLOW_REF_ICON = createIconHTML(Box, { size: 12 });
const EXIT_REF_ICON = createIconHTML(Square, { size: 12 });

export default {
  config: {
    label: "Entry",
    color: "#22c55e",
    icon: createIconSvg(Play),
    inputs: [],
    outputs: ["output"],
  },

  render(ctx) {
    const { node, nodeData, config, selected, emit } = ctx;
    const refs = nodeData.referencing_flows || [];

    const navLinks = refs.map((ref) => {
      const shortcut = ref.flow_shortcut ? ` (#${ref.flow_shortcut})` : "";
      const iconSvg = ref.node_type === "exit" ? EXIT_REF_ICON : SUBFLOW_REF_ICON;
      const navContent = html`<span style="display:inline-flex;align-items:center;gap:4px;vertical-align:middle">${unsafeSVG(iconSvg)} ${ref.flow_name}${shortcut}</span>`;
      return renderNavLink(navContent, "navigate-to-referencing-flow", "flowId", ref.flow_id, emit);
    });

    return nodeShell(config.color, selected, html`
      ${defaultHeader(config, config.color, [])}
      ${navLinks}
      <div class="content">${renderSockets(node, nodeData, this, emit)}</div>
    `);
  },

  getPreviewText(_data) {
    return "";
  },

  needsRebuild(oldData, newData) {
    const oldRefs = oldData?.referencing_flows || [];
    const newRefs = newData.referencing_flows || [];
    if (oldRefs.length !== newRefs.length) return true;
    return oldRefs.some((r, i) => r.flow_id !== newRefs[i]?.flow_id);
  },
};

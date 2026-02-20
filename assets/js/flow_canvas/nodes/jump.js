/**
 * Jump node type definition.
 */
import { html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { ArrowRight, LogOut } from "lucide";
import { createIconHTML, createIconSvg } from "../node_config.js";
import {
  defaultHeader,
  nodeShell,
  renderNavLink,
  renderPreview,
  renderSockets,
} from "./render_helpers.js";

// Pre-create navigation arrow icon
const ARROW_ICON = createIconHTML(ArrowRight, { size: 12 });

export default {
  config: {
    label: "Jump",
    color: "#a855f7",
    icon: createIconSvg(LogOut),
    inputs: ["input"],
    outputs: [],
  },

  render(ctx) {
    const { node, nodeData, config, selected, emit, hubsMap } = ctx;
    const color = this.nodeColor(nodeData, config, null, hubsMap);
    const indicators = this.getIndicators(nodeData);
    const preview = this.getPreviewText(nodeData, null, hubsMap);

    return nodeShell(
      color,
      selected,
      html`
      ${defaultHeader(config, color, indicators)}
      ${
        nodeData.target_hub_id && preview
          ? renderNavLink(preview, "navigate-to-hub", "jumpDbId", node.nodeId, emit)
          : renderPreview(preview)
      }
      <div class="content">${renderSockets(node, nodeData, this, emit)}</div>
    `,
    );
  },

  getPreviewText(data, _sheetsMap, hubsMap) {
    const targetHub = data.target_hub_id ? hubsMap?.[data.target_hub_id] : null;
    const label = targetHub?.label || data.target_hub_id;
    if (!label) return "";
    return html`<span style="display:inline-flex;align-items:center;gap:4px">${unsafeSVG(ARROW_ICON)} ${label}</span>`;
  },

  getIndicators(data) {
    const indicators = [];
    if (!data.target_hub_id) {
      indicators.push({ type: "error", title: "No target hub" });
    }
    return indicators;
  },

  nodeColor(data, config, _sheetsMap, hubsMap) {
    const targetHub = data.target_hub_id ? hubsMap?.[data.target_hub_id] : null;
    return targetHub?.color_hex || config.color;
  },

  needsRebuild(_oldData, _newData) {
    return false;
  },
};

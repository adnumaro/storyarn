/**
 * Exit node type definition.
 *
 * Represents a flow endpoint with outcome tags, color, and exit mode
 * (terminal, flow_reference, or caller_return).
 */
import { html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { ArrowRight, ArrowRightToLine, CornerDownLeft } from "lucide";
import { createIconHTML, createIconSvg } from "../node_config.js";
import {
  defaultHeader,
  nodeShell,
  renderNavLink,
  renderPreview,
  renderSockets,
} from "./render_helpers.js";

// Pre-create exit mode icons
const NAV_ARROW_ICON = createIconHTML(ArrowRight, { size: 12 });
const RETURN_ICON = createIconHTML(CornerDownLeft, { size: 12 });
const TERMINAL_ICON = createIconHTML(ArrowRightToLine);

export default {
  config: {
    label: "Exit",
    color: "#22c55e",
    icon: createIconSvg(ArrowRightToLine),
    inputs: ["input"],
    outputs: [],
  },

  render(ctx) {
    const { node, nodeData, config, selected, emit } = ctx;
    const color = this.nodeColor(nodeData, config);
    const indicators = this.getIndicators(nodeData);
    const preview = this.getPreviewText(nodeData);

    // Flow reference nav link
    let navLink = "";
    if (nodeData.exit_mode === "flow_reference" && nodeData.referenced_flow_name) {
      const shortcut = nodeData.referenced_flow_shortcut
        ? ` (#${nodeData.referenced_flow_shortcut})`
        : "";
      const navContent = html`<span class="inline-flex items-center gap-1">${unsafeSVG(NAV_ARROW_ICON)} ${nodeData.referenced_flow_name}${shortcut}</span>`;
      navLink = renderNavLink(
        navContent,
        "navigate-to-exit-flow",
        "flowId",
        nodeData.referenced_flow_id,
        emit,
      );
    }

    // Outcome tags
    const tags = nodeData.outcome_tags || [];
    const tagsText =
      tags.length > 0
        ? tags.length > 3
          ? `${tags.slice(0, 3).join(", ")} +${tags.length - 3}`
          : tags.join(", ")
        : "";

    return nodeShell(
      color,
      selected,
      html`
      ${defaultHeader(config, color, indicators)}
      ${renderPreview(preview)}
      ${navLink}
      ${tagsText ? html`<div class="text-[11px] text-base-content/80 px-3 py-2 max-w-[200px] border-b border-base-content/10 break-words"><div class="line-clamp-4 leading-[1.4] opacity-60 text-[0.7em]">${tagsText}</div></div>` : ""}
      <div class="py-1">${renderSockets(node, nodeData, this, emit)}</div>
    `,
    );
  },

  getPreviewText(data) {
    const label = data.label || "Exit";
    if (data.exit_mode === "caller_return")
      return html`<span class="inline-flex items-center gap-1">${label} ${unsafeSVG(RETURN_ICON)}</span>`;
    if (data.exit_mode === "flow_reference") return label;
    return html`<span class="inline-flex items-center gap-1">${label} ${unsafeSVG(TERMINAL_ICON)}</span>`;
  },

  getIndicators(data) {
    const indicators = [];
    if (data.exit_mode === "flow_reference" && !data.referenced_flow_id) {
      indicators.push({ type: "error", title: "No flow referenced" });
    }
    if (data.stale_reference) {
      indicators.push({ type: "error", title: "Referenced flow was deleted" });
    }
    return indicators;
  },

  nodeColor(data, _config) {
    return data.outcome_color || "#22c55e";
  },

  needsRebuild(oldData, newData) {
    if (oldData?.exit_mode !== newData.exit_mode) return true;
    if (oldData?.referenced_flow_id !== newData.referenced_flow_id) return true;
    if (oldData?.outcome_color !== newData.outcome_color) return true;
    if (JSON.stringify(oldData?.outcome_tags) !== JSON.stringify(newData.outcome_tags)) return true;
    return false;
  },
};

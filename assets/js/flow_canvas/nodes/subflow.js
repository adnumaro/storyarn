/**
 * Subflow node type definition.
 *
 * References another flow in the project with dynamic output pins
 * generated from the referenced flow's Exit nodes.
 */
import { html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { ArrowRight, Box, CornerDownLeft, Square } from "lucide";
import { createIconHTML, createIconSvg } from "../node_config.js";
import { defaultHeader, nodeShell, renderNavLink, renderSockets } from "./render_helpers.js";

// Pre-create icons for nav link and exit mode labels
const NAV_ARROW_ICON = createIconHTML(ArrowRight, { size: 12 });
const RETURN_ICON = createIconHTML(CornerDownLeft);
const TERMINAL_ICON = createIconHTML(Square);

export default {
  config: {
    label: "Subflow",
    color: "#6366f1",
    icon: createIconSvg(Box),
    inputs: ["input"],
    outputs: ["output"],
    dynamicOutputs: true,
  },

  /**
   * Dynamic outputs: one per Exit node in referenced flow.
   * Exits with exit_mode "flow_reference" route themselves and are excluded.
   */
  createOutputs(data) {
    if (data.exit_labels?.length > 0) {
      const relevantExits = data.exit_labels.filter((e) => e.exit_mode !== "flow_reference");
      if (relevantExits.length > 0) {
        return relevantExits.map((e) => `exit_${e.id}`);
      }
    }
    return null; // Fall back to static ["output"]
  },

  formatOutputLabel(key, data) {
    if (key.startsWith("exit_")) {
      const exitId = parseInt(key.replace("exit_", ""), 10);
      const exit = data.exit_labels?.find((e) => e.id === exitId);
      if (exit) {
        const modeIconSvg = exit.exit_mode === "caller_return" ? RETURN_ICON : TERMINAL_ICON;
        const label = exit.label || "Exit";
        return html`<span style="display:inline-flex;align-items:center;gap:3px">${unsafeSVG(modeIconSvg)} ${label}</span>`;
      }
      return "Exit";
    }
    return "Output";
  },

  getOutputBadges(_key, _data) {
    return [];
  },

  render(ctx) {
    const { node, nodeData, config, selected, emit } = ctx;
    const color = this.nodeColor(nodeData, config);
    const indicators = this.getIndicators(nodeData);
    let navContent = null;
    if (nodeData.referenced_flow_name) {
      const shortcut = nodeData.referenced_flow_shortcut
        ? ` (#${nodeData.referenced_flow_shortcut})`
        : "";
      navContent = html`<span style="display:inline-flex;align-items:center;gap:4px">${unsafeSVG(NAV_ARROW_ICON)} ${nodeData.referenced_flow_name}${shortcut}</span>`;
    }

    return nodeShell(
      color,
      selected,
      html`
      ${defaultHeader(config, color, indicators)}
      ${
        navContent
          ? renderNavLink(
              navContent,
              "navigate-to-subflow",
              "flowId",
              nodeData.referenced_flow_id,
              emit,
            )
          : ""
      }
      ${!nodeData.referenced_flow_id ? html`<div class="node-data"><div class="node-data-text" style="opacity:0.5">No flow selected</div></div>` : ""}
      <div class="content">${renderSockets(node, nodeData, this, emit)}</div>
    `,
    );
  },

  getIndicators(data) {
    const indicators = [];
    if (!data.referenced_flow_id) {
      indicators.push({ type: "error", title: "No flow referenced" });
    }
    if (data.stale_reference) {
      indicators.push({ type: "error", title: "Referenced flow was deleted" });
    }
    return indicators;
  },

  getPreviewText(_data) {
    return "";
  },

  nodeColor(_data, config) {
    return config.color;
  },

  needsRebuild(oldData, newData) {
    if (oldData?.referenced_flow_id !== newData.referenced_flow_id) return true;
    const oldExits = oldData?.exit_labels || [];
    const newExits = newData.exit_labels || [];
    if (oldExits.length !== newExits.length) return true;
    return oldExits.some(
      (e, i) => e.id !== newExits[i]?.id || e.exit_mode !== newExits[i]?.exit_mode,
    );
  },
};

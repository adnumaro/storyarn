/**
 * Subflow node type definition.
 *
 * References another flow in the project with dynamic output pins
 * generated from the referenced flow's Exit nodes.
 */
import { html } from "lit";
import { Box } from "lucide";
import { createIconSvg } from "../node_config.js";
import { nodeShell, defaultHeader, renderNavLink, renderSockets } from "./render_helpers.js";

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
   */
  createOutputs(data) {
    if (data.exit_labels?.length > 0) {
      return data.exit_labels.map((e) => `exit_${e.id}`);
    }
    return null; // Fall back to static ["output"]
  },

  formatOutputLabel(key, data) {
    if (key.startsWith("exit_")) {
      const exitId = parseInt(key.replace("exit_", ""));
      const exit = data.exit_labels?.find((e) => e.id === exitId);
      if (exit) {
        const icon = exit.is_success === false ? "✕" : "✓";
        return `${icon} ${exit.label || "Exit"}`;
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
    const preview = this.getPreviewText(nodeData);

    let navText = null;
    if (nodeData.referenced_flow_name) {
      const shortcut = nodeData.referenced_flow_shortcut ? ` (#${nodeData.referenced_flow_shortcut})` : "";
      navText = `\u2192 ${nodeData.referenced_flow_name}${shortcut}`;
    }

    return nodeShell(color, selected, html`
      ${defaultHeader(config, color, indicators)}
      ${navText
        ? renderNavLink(navText, "navigate-to-subflow", "flowId", nodeData.referenced_flow_id, emit)
        : ""}
      ${!nodeData.referenced_flow_id ? html`<div class="node-data"><div class="node-data-text" style="opacity:0.5">No flow selected</div></div>` : ""}
      <div class="content">${renderSockets(node, nodeData, this, emit)}</div>
    `);
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
    return oldExits.some((e, i) => e.id !== newExits[i]?.id);
  },
};

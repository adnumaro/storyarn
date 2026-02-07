/**
 * Entry node type definition.
 */
import { html } from "lit";
import { Play } from "lucide";
import { createIconSvg } from "../node_config.js";
import { nodeShell, defaultHeader, renderSockets } from "./render_helpers.js";

export default {
  config: {
    label: "Entry",
    color: "#22c55e",
    icon: createIconSvg(Play),
    inputs: [],
    outputs: ["output"],
  },

  render(ctx) {
    const { node, config, selected, emit } = ctx;
    return nodeShell(config.color, selected, html`
      ${defaultHeader(config, config.color, [])}
      <div class="content">${renderSockets(node, {}, this, emit)}</div>
    `);
  },

  getPreviewText(_data) {
    return "";
  },

  needsRebuild(_oldData, _newData) {
    return false;
  },
};

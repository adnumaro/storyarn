/**
 * StoryarnNode - Custom LitElement component for rendering flow nodes.
 *
 * Thin shell that delegates all rendering to per-type node definitions.
 * Supports two LOD tiers: "full" (per-type render) and "simplified"
 * (generic header + bare sockets, no labels/badges/previews).
 */

import { html, LitElement } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { getNodeDef, NODE_CONFIGS } from "../node_config.js";
import { storyarnNodeStyles } from "./storyarn_node_styles.js";

export class StoryarnNode extends LitElement {
  static get properties() {
    return {
      data: { type: Object },
      emit: { type: Function },
      sheetsMap: { type: Object },
      hubsMap: { type: Object },
      lod: { type: String },
    };
  }

  static styles = storyarnNodeStyles;

  render() {
    const node = this.data;
    if (!node) return html``;

    // Simplified LOD — generic minimal render
    if (this.lod === "simplified") {
      const config = NODE_CONFIGS[node.nodeType] || NODE_CONFIGS.dialogue;
      const color = this.getSimplifiedColor(node, config);
      const borderColor = `${color}40`;
      return html`
        <div
          class="node simplified ${node.selected ? "selected" : ""}"
          style="--node-border-color: ${borderColor}"
        >
          <div class="header" style="background-color: ${color}">
            <span class="icon">${unsafeSVG(config.icon)}</span>
            <span>${config.label}</span>
          </div>
          <div class="content">${this.renderSimplifiedSockets(node)}</div>
        </div>
      `;
    }

    // Full render (per-type delegation, unchanged)
    const def = getNodeDef(node.nodeType);
    const config = NODE_CONFIGS[node.nodeType] || NODE_CONFIGS.dialogue;

    return def.render({
      node,
      nodeData: node.nodeData || {},
      config,
      selected: node.selected,
      emit: this.emit,
      sheetsMap: this.sheetsMap,
      hubsMap: this.hubsMap,
    });
  }

  /** All sockets rendered as bare rete-ref elements (no labels/badges). */
  renderSimplifiedSockets(node) {
    const inputs = Object.entries(node.inputs || {});
    const outputs = Object.entries(node.outputs || {});

    return html`
      ${inputs.map(
        ([key, input]) => html`
          <div class="socket-row input">
            <rete-ref
              class="input-socket"
              .data=${{
                type: "socket",
                side: "input",
                key,
                nodeId: node.id,
                payload: input.socket,
              }}
              .emit=${this.emit}
            ></rete-ref>
          </div>
        `,
      )}
      ${outputs.map(
        ([key, output]) => html`
          <div class="socket-row output">
            <rete-ref
              class="output-socket"
              .data=${{
                type: "socket",
                side: "output",
                key,
                nodeId: node.id,
                payload: output.socket,
              }}
              .emit=${this.emit}
            ></rete-ref>
          </div>
        `,
      )}
    `;
  }

  /** Get node color without calling per-type render. */
  getSimplifiedColor(node, config) {
    const d = node.nodeData || {};
    // Speaker color for dialogue
    if (node.nodeType === "dialogue" && d.speaker_sheet_id) {
      const sheet = this.sheetsMap?.[String(d.speaker_sheet_id)];
      if (sheet?.color) return sheet.color;
    }
    // Hub custom color
    if (node.nodeType === "hub" && d.color_hex) return d.color_hex;
    // Exit custom color
    if (node.nodeType === "exit" && d.color_hex) return d.color_hex;
    return config.color;
  }
}

customElements.define("storyarn-node", StoryarnNode);

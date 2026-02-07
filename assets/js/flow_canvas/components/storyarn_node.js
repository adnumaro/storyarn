/**
 * StoryarnNode - Custom LitElement component for rendering flow nodes.
 *
 * Thin shell that delegates all rendering to per-type node definitions.
 */

import { LitElement, html } from "lit";
import { NODE_CONFIGS, getNodeDef } from "../node_config.js";
import { storyarnNodeStyles } from "./storyarn_node_styles.js";

export class StoryarnNode extends LitElement {
  static get properties() {
    return {
      data: { type: Object },
      emit: { type: Function },
      sheetsMap: { type: Object },
      hubsMap: { type: Object },
    };
  }

  static styles = storyarnNodeStyles;

  render() {
    const node = this.data;
    if (!node) return html``;

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
}

customElements.define("storyarn-node", StoryarnNode);

/**
 * StoryarnNode - Custom LitElement component for rendering flow nodes.
 *
 * Thin shell that delegates all rendering to per-type node definitions.
 * Supports two LOD tiers: "full" (per-type render) and "simplified"
 * (generic header + bare sockets, no labels/badges/previews).
 */

import { html, LitElement } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { adoptTailwind } from "../../utils/shadow_styles.js";
import { getNodeDef, NODE_CONFIGS } from "../node_config.js";
import { storyarnNodeStyles } from "./storyarn_node_styles.js";

export class StoryarnNode extends LitElement {
  static get properties() {
    return {
      data: { type: Object },
      emit: { type: Function },
      sheetsMap: { type: Object },
      hubsMap: { type: Object },
      labels: { type: Object },
      lod: { type: String },
      editing: { type: Boolean },
    };
  }

  static styles = storyarnNodeStyles;

  connectedCallback() {
    super.connectedCallback();
    // Expose a readiness promise so the hook can measure after Shadow DOM
    // Tailwind has actually been adopted for this node instance.
    this._tailwindReady = adoptTailwind(this.shadowRoot);
  }

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
          class="node relative bg-base-200 rounded-xl min-w-[120px] border-[1.5px] ${node.selected ? "selected" : ""}"
          style="--node-border-color: ${borderColor}; --node-color: ${color}; border-color: var(--node-border-color, transparent)"
        >
          <div class="px-3 py-2 rounded-t-[10px] flex items-center gap-2 text-white font-medium text-[13px]" style="background-color: ${color}">
            <span class="flex items-center">${unsafeSVG(config.icon)}</span>
            <span>${config.label}</span>
          </div>
          <div class="py-0.5">${this.renderSimplifiedSockets(node)}</div>
        </div>
      `;
    }

    // Full render (per-type delegation, unchanged)
    const def = getNodeDef(node.nodeType);
    const config = NODE_CONFIGS[node.nodeType] || NODE_CONFIGS.dialogue;

    const ctx = {
      node,
      nodeData: node.nodeData || {},
      config,
      selected: node.selected,
      emit: this.emit,
      sheetsMap: this.sheetsMap,
      hubsMap: this.hubsMap,
      labels: this.labels,
    };

    // Inline edit mode for dialogue and annotation nodes
    if (
      this.editing &&
      (node.nodeType === "dialogue" || node.nodeType === "annotation") &&
      def.renderEdit
    ) {
      ctx.onSave = (field, value) => {
        this.dispatchEvent(
          new CustomEvent("node-inline-edit", {
            bubbles: true,
            composed: true,
            detail: { field, value },
          }),
        );
      };
      return def.renderEdit(ctx);
    }

    return def.render(ctx);
  }

  updated(changedProperties) {
    super.updated(changedProperties);
    if (changedProperties.has("editing") && this.editing) {
      // Auto-size textarea fallback for browsers without field-sizing: content
      requestAnimationFrame(() => {
        const textarea = this.shadowRoot?.querySelector(".inline-textarea");
        if (textarea) {
          textarea.style.height = "auto";
          textarea.style.height = `${textarea.scrollHeight}px`;
        }
      });
    }
  }

  /** All sockets rendered as bare rete-ref elements (no labels/badges). */
  renderSimplifiedSockets(node) {
    const inputs = Object.entries(node.inputs || {});
    const outputs = Object.entries(node.outputs || {});

    return html`
      ${inputs.map(
        ([key, input]) => html`
          <div class="flex items-center py-0.5 text-[11px] text-base-content/70 justify-start">
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
          <div class="flex items-center py-0.5 text-[11px] text-base-content/70 justify-end">
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
    // Annotation color
    if (node.nodeType === "annotation") return d.color || "#fbbf24";
    return config.color;
  }
}

customElements.define("storyarn-node", StoryarnNode);

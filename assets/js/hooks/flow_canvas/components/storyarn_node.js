/**
 * StoryarnNode - Custom LitElement component for rendering flow nodes.
 */

import { LitElement, css, html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { NODE_CONFIGS } from "../node_config.js";

export class StoryarnNode extends LitElement {
  static get properties() {
    return {
      data: { type: Object },
      emit: { type: Function },
      pagesMap: { type: Object },
    };
  }

  // Shadow DOM styles using daisyUI CSS variables (they pierce Shadow DOM)
  static styles = css`
    :host {
      display: block;
    }

    .node {
      background: oklch(var(--b1, 0.2 0 0));
      border-radius: 8px;
      min-width: 180px;
      box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
      border: 1.5px solid var(--node-border-color, transparent);
      transition: box-shadow 0.2s;
    }

    .node:hover {
      box-shadow: 0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);
    }

    .node.selected {
      box-shadow: 0 0 0 3px oklch(var(--p, 0.6 0.2 250) / 0.5), 0 4px 6px -1px rgb(0 0 0 / 0.1);
    }

    .header {
      padding: 8px 12px;
      border-radius: 6px 6px 0 0;
      display: flex;
      align-items: center;
      gap: 8px;
      color: white;
      font-weight: 500;
      font-size: 13px;
    }

    .icon {
      display: flex;
      align-items: center;
    }

    .content {
      padding: 8px 0;
    }

    .socket-row {
      display: flex;
      align-items: center;
      padding: 4px 0;
      font-size: 11px;
      color: oklch(var(--bc, 0.8 0 0) / 0.7);
    }

    .socket-row.input {
      justify-content: flex-start;
      padding-left: 0;
    }

    .socket-row.output {
      justify-content: flex-end;
      padding-right: 0;
    }

    .socket-row .label {
      padding: 0 8px;
    }

    .input-socket {
      margin-left: -10px;
    }

    .output-socket {
      margin-right: -10px;
    }

    .node-data {
      font-size: 11px;
      color: oklch(var(--bc, 0.8 0 0) / 0.6);
      padding: 4px 12px 8px;
      max-width: 160px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .condition-badge {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 14px;
      height: 14px;
      font-size: 10px;
      font-weight: bold;
      background: oklch(var(--wa, 0.8 0.15 80) / 0.2);
      color: oklch(var(--wa, 0.8 0.15 80));
      border-radius: 50%;
      margin-right: 2px;
    }
  `;

  render() {
    const node = this.data;
    if (!node) return html``;

    const config = NODE_CONFIGS[node.nodeType] || NODE_CONFIGS.dialogue;
    const nodeData = node.nodeData || {};

    // Get preview text based on node type
    const preview = this.getPreviewText(node.nodeType, nodeData);

    // Calculate border color with opacity
    const borderColor = `${config.color}40`;

    return html`
      <div
        class="node ${node.selected ? "selected" : ""}"
        style="--node-border-color: ${borderColor}"
      >
        <div class="header" style="background-color: ${config.color}">
          <span class="icon">${unsafeSVG(config.icon)}</span>
          <span>${config.label}</span>
        </div>
        <div class="content">
          ${Object.entries(node.inputs || {}).map(
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
                <span class="label">${key}</span>
              </div>
            `,
          )}
          ${Object.entries(node.outputs || {}).map(([key, output]) => {
            // For dialogue nodes with responses, show response text as label
            let outputLabel = key;
            let hasCondition = false;
            if (node.nodeType === "dialogue" && nodeData.responses?.length > 0) {
              const response = nodeData.responses.find((r) => r.id === key);
              outputLabel = response?.text || key;
              hasCondition = !!response?.condition;
            }
            return html`
              <div class="socket-row output">
                ${hasCondition ? html`<span class="condition-badge" title="Has condition">?</span>` : ""}
                <span class="label" title="${outputLabel}">${outputLabel}</span>
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
            `;
          })}
        </div>
        ${preview ? html`<div class="node-data">${preview}</div>` : ""}
      </div>
    `;
  }

  getPreviewText(nodeType, nodeData) {
    switch (nodeType) {
      case "dialogue": {
        // Resolve speaker name from pagesMap
        const speakerId = nodeData.speaker_page_id;
        const speakerPage = speakerId ? this.pagesMap?.[String(speakerId)] : null;
        const speakerName = speakerPage?.name || "";
        // Strip HTML from text for preview
        const textContent = nodeData.text
          ? new DOMParser().parseFromString(nodeData.text, "text/html").body.textContent
          : "";
        return speakerName || textContent || "";
      }
      case "hub":
        return nodeData.label || "";
      case "condition":
        return nodeData.expression || "";
      case "instruction":
        return nodeData.action || "";
      case "jump":
        return nodeData.target_flow || "";
      default:
        return "";
    }
  }
}

customElements.define("storyarn-node", StoryarnNode);

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

    .stage-directions {
      font-style: italic;
      color: oklch(var(--bc, 0.8 0 0) / 0.5);
      font-size: 10px;
      padding: 2px 12px 4px;
      max-width: 160px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .speaker-avatar {
      width: 20px;
      height: 20px;
      border-radius: 50%;
      object-fit: cover;
      flex-shrink: 0;
    }

    .speaker-name {
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

    .audio-indicator {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      margin-left: auto;
      opacity: 0.8;
    }

    .audio-indicator svg {
      width: 12px;
      height: 12px;
    }

    .header-indicators {
      display: flex;
      align-items: center;
      gap: 4px;
      margin-left: auto;
    }

    .logic-indicator {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 10px;
      opacity: 0.9;
    }

    .logic-indicator.input-condition {
      color: rgba(255, 255, 255, 0.9);
    }

    .logic-indicator.output-instruction {
      color: rgba(255, 255, 255, 0.9);
    }
  `;

  render() {
    const node = this.data;
    if (!node) return html``;

    const config = NODE_CONFIGS[node.nodeType] || NODE_CONFIGS.dialogue;
    const nodeData = node.nodeData || {};

    // Get preview text based on node type (not used for dialogue with speaker)
    const preview = this.getPreviewText(node.nodeType, nodeData);
    const stageDirections = nodeData.stage_directions || "";

    // Calculate border color with opacity
    const borderColor = `${config.color}40`;

    // For dialogue nodes, check if there's a speaker
    const isDialogue = node.nodeType === "dialogue";
    const speakerId = nodeData.speaker_page_id;
    const speakerPage = speakerId ? this.pagesMap?.[String(speakerId)] : null;
    const hasAudio = isDialogue && nodeData.audio_asset_id;

    // Logic indicators for dialogue nodes
    const hasInputCondition = isDialogue && nodeData.input_condition;
    const hasOutputInstruction = isDialogue && nodeData.output_instruction;

    // Debug logging
    if (isDialogue) {
      console.log("[StoryarnNode] Rendering dialogue:", {
        nodeId: node.nodeId,
        speakerId,
        speakerPage,
        hasAudio,
        hasInputCondition,
        hasOutputInstruction,
        pagesMapKeys: Object.keys(this.pagesMap || {}),
      });
    }

    // Audio icon SVG
    const audioIcon = `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/></svg>`;

    // Check if we need to show any header indicators
    const showIndicators = hasAudio || hasInputCondition || hasOutputInstruction;

    return html`
      <div
        class="node ${node.selected ? "selected" : ""}"
        style="--node-border-color: ${borderColor}"
      >
        <div class="header" style="background-color: ${config.color}">
          ${
            isDialogue && speakerPage
              ? html`
                ${
                  speakerPage.avatar_url
                    ? html`<img src="${speakerPage.avatar_url}" class="speaker-avatar" alt="" />`
                    : html`<span class="icon">${unsafeSVG(config.icon)}</span>`
                }
                <span class="speaker-name">${speakerPage.name}</span>
              `
              : html`
                <span class="icon">${unsafeSVG(config.icon)}</span>
                <span>${config.label}</span>
              `
          }
          ${showIndicators ? html`
            <span class="header-indicators">
              ${hasInputCondition ? html`<span class="logic-indicator input-condition" title="Has input condition">🔒</span>` : ""}
              ${hasOutputInstruction ? html`<span class="logic-indicator output-instruction" title="Has output instruction">⚡</span>` : ""}
              ${hasAudio ? html`<span class="audio-indicator" title="Has audio">${unsafeSVG(audioIcon)}</span>` : ""}
            </span>
          ` : ""}
        </div>
        ${
          isDialogue && stageDirections
            ? html`<div class="stage-directions">${stageDirections}</div>`
            : ""
        }
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
            // For condition nodes with cases, show case label
            if (node.nodeType === "condition" && nodeData.cases?.length > 0) {
              const caseItem = nodeData.cases.find((c) => c.id === key);
              outputLabel = caseItem?.label || caseItem?.value || key;
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
        // Strip HTML from text for preview (speaker name is now shown in header)
        const textContent = nodeData.text
          ? new DOMParser().parseFromString(nodeData.text, "text/html").body.textContent
          : "";
        return textContent || "";
      }
      case "hub":
        return nodeData.hub_id || "";
      case "condition":
        return nodeData.expression || "";
      case "instruction":
        return nodeData.action || "";
      case "jump":
        return nodeData.target_hub_id ? `→ ${nodeData.target_hub_id}` : "";
      case "exit":
        return nodeData.label || "";
      default:
        return "";
    }
  }
}

customElements.define("storyarn-node", StoryarnNode);

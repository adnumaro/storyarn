/**
 * StoryarnNode - Custom LitElement component for rendering flow nodes.
 */

import { LitElement, html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { createElement, TriangleAlert, Volume2 } from "lucide";
import { NODE_CONFIGS } from "../node_config.js";
import { storyarnNodeStyles } from "./storyarn_node_styles.js";
import {
  getPreviewText,
  formatRuleShort,
  isRuleComplete,
  getRuleErrorMessage,
} from "./node_formatters.js";

export class StoryarnNode extends LitElement {
  static get properties() {
    return {
      data: { type: Object },
      emit: { type: Function },
      pagesMap: { type: Object },
    };
  }

  static styles = storyarnNodeStyles;

  render() {
    const node = this.data;
    if (!node) return html``;

    const config = NODE_CONFIGS[node.nodeType] || NODE_CONFIGS.dialogue;
    const nodeData = node.nodeData || {};

    const preview = getPreviewText(node.nodeType, nodeData);
    const stageDirections = nodeData.stage_directions || "";

    const isDialogue = node.nodeType === "dialogue";
    const speakerId = nodeData.speaker_page_id;
    const speakerPage = speakerId ? this.pagesMap?.[String(speakerId)] : null;
    const hasAudio = isDialogue && nodeData.audio_asset_id;

    const hasInputCondition = isDialogue && nodeData.input_condition;
    const hasOutputInstruction = isDialogue && nodeData.output_instruction;

    const nodeColor = (isDialogue && speakerPage?.color) || config.color;
    const borderColor = `${nodeColor}40`;

    const audioIconEl = createElement(Volume2);
    audioIconEl.setAttribute("width", "12");
    audioIconEl.setAttribute("height", "12");
    const audioIcon = audioIconEl.outerHTML;

    const alertIconEl = createElement(TriangleAlert);
    alertIconEl.setAttribute("width", "10");
    alertIconEl.setAttribute("height", "10");
    const alertIcon = alertIconEl.outerHTML;

    const showIndicators = hasAudio || hasInputCondition || hasOutputInstruction;

    return html`
      <div
        class="node ${node.selected ? "selected" : ""}"
        style="--node-border-color: ${borderColor}"
      >
        <div class="header" style="background-color: ${nodeColor}">
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
          ${
            showIndicators
              ? html`
            <span class="header-indicators">
              ${hasInputCondition ? html`<span class="logic-indicator input-condition" title="Has input condition">🔒</span>` : ""}
              ${hasOutputInstruction ? html`<span class="logic-indicator output-instruction" title="Has output instruction">⚡</span>` : ""}
              ${hasAudio ? html`<span class="audio-indicator" title="Has audio">${unsafeSVG(audioIcon)}</span>` : ""}
            </span>
          `
              : ""
          }
        </div>
        ${
          isDialogue && stageDirections
            ? html`<div class="stage-directions">${stageDirections}</div>`
            : ""
        }
        ${preview ? html`<div class="node-data"><div class="node-data-text">${preview}</div></div>` : ""}
        <div class="content">
          ${this.renderSockets(node, nodeData, alertIcon)}
        </div>
      </div>
    `;
  }

  /**
   * Renders sockets based on node type and configuration.
   */
  renderSockets(node, nodeData, alertIcon) {
    const inputs = Object.entries(node.inputs || {});
    const outputs = Object.entries(node.outputs || {});
    const hasResponses = node.nodeType === "dialogue" && nodeData.responses?.length > 0;
    const isCondition = node.nodeType === "condition";

    if (inputs.length === 1 && outputs.length === 1 && !hasResponses && !isCondition) {
      const [inputKey, input] = inputs[0];
      const [outputKey, output] = outputs[0];

      return html`
        <div class="sockets-row">
          <rete-ref
            class="input-socket"
            .data=${{
              type: "socket",
              side: "input",
              key: inputKey,
              nodeId: node.id,
              payload: input.socket,
            }}
            .emit=${this.emit}
          ></rete-ref>
          <span class="socket-label-left">${inputKey}</span>
          <span class="socket-label-right">${outputKey}</span>
          <rete-ref
            class="output-socket"
            .data=${{
              type: "socket",
              side: "output",
              key: outputKey,
              nodeId: node.id,
              payload: output.socket,
            }}
            .emit=${this.emit}
          ></rete-ref>
        </div>
      `;
    }

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
      ${outputs.map(([key, output]) => {
        let outputLabel = key;
        let hasCondition = false;
        let hasError = false;
        let errorMessage = "";

        if (hasResponses) {
          const response = nodeData.responses.find((r) => r.id === key);
          outputLabel = response?.text || key;
          hasCondition = !!response?.condition;
        }

        if (isCondition) {
          if (nodeData.switch_mode && nodeData.condition?.rules?.length > 0) {
            if (key === "default") {
              outputLabel = "Default";
            } else {
              const rule = nodeData.condition.rules.find((r) => r.id === key);
              outputLabel = rule?.label || formatRuleShort(rule) || key;
              if (rule && !isRuleComplete(rule)) {
                hasError = true;
                errorMessage = getRuleErrorMessage(rule);
              }
            }
          } else {
            outputLabel = key === "true" ? "True" : key === "false" ? "False" : key;
          }
        }

        return html`
          <div class="socket-row output">
            ${hasError ? html`<div class="error-badge" title="${errorMessage}">${unsafeSVG(alertIcon)}</div>` : ""}
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
    `;
  }
}

customElements.define("storyarn-node", StoryarnNode);

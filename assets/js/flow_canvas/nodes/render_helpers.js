/**
 * Shared rendering primitives for per-type node render() methods.
 * Pure functions returning Lit html templates — no class, no state.
 */

import { html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { TriangleAlert, Volume2 } from "lucide";
import { createIconHTML } from "../node_config.js";

// Pre-create icon SVGs (shared across all node types)
const AUDIO_ICON = createIconHTML(Volume2, { size: 12 });
const ALERT_ICON = createIconHTML(TriangleAlert);

/**
 * Outer node wrapper with border color and selection state.
 */
export function nodeShell(nodeColor, selected, content) {
  const borderColor = `${nodeColor}40`;
  return html`
    <div
      class="node ${selected ? "selected" : ""}"
      style="--node-border-color: ${borderColor}"
    >
      ${content}
    </div>
  `;
}

/**
 * Default header with icon + label.
 */
export function defaultHeader(config, nodeColor, indicators) {
  return html`
    <div class="header" style="background-color: ${nodeColor}">
      <span class="icon">${unsafeSVG(config.icon)}</span>
      <span>${config.label}</span>
      ${renderIndicators(indicators)}
    </div>
  `;
}

/**
 * Speaker header with avatar (or icon fallback) + name.
 */
export function speakerHeader(config, nodeColor, speakerSheet, indicators) {
  return html`
    <div class="header" style="background-color: ${nodeColor}">
      ${
        speakerSheet.avatar_url
          ? html`<img src="${speakerSheet.avatar_url}" class="speaker-avatar" alt="" />`
          : html`<span class="icon">${unsafeSVG(config.icon)}</span>`
      }
      <span class="speaker-name">${speakerSheet.name}</span>
      ${renderIndicators(indicators)}
    </div>
  `;
}

/**
 * Renders indicator badges in the header.
 */
export function renderIndicators(indicators) {
  if (!indicators || indicators.length === 0) return "";
  return html`
    <span class="header-indicators">
      ${indicators.map((ind) => {
        if (ind.type === "audio")
          return html`<span class="audio-indicator" title="${ind.title}"
            >${unsafeSVG(AUDIO_ICON)}</span
          >`;
        if (ind.type === "error")
          return html`<span class="error-badge" title="${ind.title}"
            >${unsafeSVG(ALERT_ICON)}</span
          >`;
        if (ind.svg)
          return html`<span class="logic-indicator ${ind.class || ""}" title="${ind.title}"
            >${unsafeSVG(ind.svg)}</span
          >`;
        return html`<span
          class="logic-indicator ${ind.class || ""}"
          title="${ind.title}"
          >${ind.text}</span
        >`;
      })}
    </span>
  `;
}

/**
 * Renders preview text block.
 */
export function renderPreview(text) {
  if (!text) return "";
  return html`<div class="node-data"><div class="node-data-text">${text}</div></div>`;
}

/**
 * Renders a clickable navigation link block (used by hub/jump).
 */
export function renderNavLink(text, event, detailKey, nodeId, _emit) {
  return html`<div class="node-data">
    <div
      class="node-data-text nav-link"
      @pointerdown=${(e) => {
        e.stopPropagation();
        e.target.dispatchEvent(
          new CustomEvent(event, {
            bubbles: true,
            composed: true,
            detail: { [detailKey]: nodeId },
          }),
        );
      }}
    >
      ${text}
    </div>
  </div>`;
}

/**
 * Renders sockets (inputs + outputs) for a node.
 * Handles the single-row optimisation (1 input + 1 output) and the multi-row layout.
 *
 * @param {object}   node     - Full node data (has .inputs, .outputs, .id)
 * @param {object}   nodeData - The node's domain data
 * @param {object}   def      - Per-type definition (for config.dynamicOutputs, formatOutputLabel, getOutputBadges)
 * @param {Function} emit     - Rete emit function
 */
export function renderSockets(node, nodeData, def, emit) {
  const inputs = Object.entries(node.inputs || {});
  const outputs = Object.entries(node.outputs || {});
  if (inputs.length === 1 && outputs.length === 1 && !def?.config?.dynamicOutputs) {
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
          .emit=${emit}
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
          .emit=${emit}
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
            .emit=${emit}
          ></rete-ref>
        </div>
      `,
    )}
    ${outputs.map(([key, output]) => {
      const outputLabel = def?.formatOutputLabel?.(key, nodeData) ?? key;
      const badges = def?.getOutputBadges?.(key, nodeData) || [];
      const labelTitle = typeof outputLabel === "string" ? outputLabel : key;

      return html`
        <div class="socket-row output">
          ${badges.map((badge) =>
            badge.type === "error"
              ? html`<div class="error-badge" title="${badge.title}">${unsafeSVG(ALERT_ICON)}</div>`
              : html`<span class="${badge.class}" title="${badge.title}">${badge.text}</span>`,
          )}
          <span class="label" title="${labelTitle}">${outputLabel}</span>
          <rete-ref
            class="output-socket"
            .data=${{
              type: "socket",
              side: "output",
              key,
              nodeId: node.id,
              payload: output.socket,
            }}
            .emit=${emit}
          ></rete-ref>
        </div>
      `;
    })}
  `;
}
